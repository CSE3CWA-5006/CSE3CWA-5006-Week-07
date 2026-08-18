/*
 * Smart City IoT Operations Console - Express backend
 * Copyright (c) 2026 Dr Shuo Ding <shuoding@outlook.com>
 * Licensed under AGPL-3.0-or-later. See LICENSE.
 */
import "dotenv/config";
import cors from "cors";
import express from "express";
import morgan from "morgan";
import mqtt from "mqtt";
import { MongoClient } from "mongodb";

const config = {
  port: Number(process.env.PORT || 4100),
  frontendOrigin: process.env.FRONTEND_ORIGIN || "http://localhost:5174",
  mqttBrokerUrl: process.env.MQTT_BROKER_URL || "mqtt://localhost:1883",
  mqttSubscribeTopic: process.env.MQTT_SUBSCRIBE_TOPIC || "latrobe/+/+/+/+",
  uiControlTopic: "latrobe/ui/mode",
  mongodbUri: process.env.MONGODB_URI || "mongodb://127.0.0.1:27017",
  mongodbDb: process.env.MONGODB_DB || "week7_iot",
  mongodbCollection: process.env.MONGODB_COLLECTION || "sensor_readings",
  sseIntervalMs: Number(process.env.SSE_INTERVAL_MS || 5000)
};

const app = express();
app.use(cors({ origin: config.frontendOrigin }));
app.use(express.json());
app.use(morgan("dev"));

let mongoClient;
let readings;
let mqttClient;
const sseClients = new Set();
let uiMode = "environment";

const runtime = {
  mqttConnected: false,
  mongodbConnected: false,
  receivedMessages: 0,
  storedMessages: 0,
  lastMessageAt: null,
  lastError: null
};

function parseJsonPayload(buffer) {
  try { return JSON.parse(buffer.toString("utf8")); }
  catch (error) { throw new Error(`Invalid JSON payload: ${error.message}`); }
}

function parseTopic(topic) {
  const [campus, building, level, room, sensorType] = topic.split("/");
  return {
    campus: campus || "unknown",
    building: building || "unknown",
    level: level || "unknown",
    room: room || "unknown",
    sensorType: sensorType || "unknown"
  };
}

function normaliseReading(topic, payload) {
  const topicInfo = parseTopic(topic);
  return {
    topic,
    deviceId: String(payload.deviceId || "unknown-device"),
    sensorType: String(payload.sensorType || topicInfo.sensorType),
    value: Number(payload.value),
    unit: String(payload.unit || ""),
    observedAt: payload.observedAt ? new Date(payload.observedAt) : new Date(),
    receivedAt: new Date(),
    sequence: Number(payload.sequence || 0),
    location: {
      campus: topicInfo.campus,
      building: topicInfo.building,
      level: topicInfo.level,
      room: topicInfo.room
    },
    rawPayload: payload
  };
}

function isValidReading(reading) {
  return reading.deviceId !== "unknown-device" &&
    reading.sensorType !== "unknown" &&
    Number.isFinite(reading.value) &&
    reading.observedAt instanceof Date &&
    !Number.isNaN(reading.observedAt.getTime());
}

const readingProjection = {
  _id: 0, topic: 1, deviceId: 1, sensorType: 1, value: 1, unit: 1,
  observedAt: 1, receivedAt: 1, sequence: 1, location: 1
};

function isParkingReading(reading) {
  return reading?.sensorType === "occupancy" && String(reading?.location?.building || "").startsWith("carpark-");
}

async function storeReading(topic, message) {
  runtime.receivedMessages += 1;
  runtime.lastMessageAt = new Date().toISOString();
  const payload = parseJsonPayload(message);
  const reading = normaliseReading(topic, payload);
  if (!isValidReading(reading)) throw new Error(`Rejected invalid reading from topic ${topic}`);
  await readings.insertOne(reading);
  runtime.storedMessages += 1;
  console.log(`[STORE] ${reading.sensorType} ${reading.value} ${reading.unit} from ${reading.deviceId}`);
  if (isParkingReading(reading)) broadcast("parking-data", { reading });
}

async function getLatestReadings() {
  return readings.aggregate([
    { $sort: { receivedAt: -1 } },
    { $group: {
      _id: { building: "$location.building", level: "$location.level", room: "$location.room", sensorType: "$sensorType" },
      reading: { $first: "$$ROOT" }
    } },
    { $replaceRoot: { newRoot: "$reading" } },
    { $sort: { "location.building": 1, "location.level": 1, "location.room": 1, sensorType: 1 } },
    { $project: readingProjection }
  ]).toArray();
}

async function getSensorTypes() {
  const types = await readings.distinct("sensorType", { sensorType: { $ne: "occupancy" } });
  return types.sort();
}

async function getRooms() {
  const rows = await readings.aggregate([
    { $match: { sensorType: { $ne: "occupancy" }, "location.room": { $ne: "unknown" } } },
    { $group: { _id: { building: "$location.building", level: "$location.level", room: "$location.room" } } },
    { $sort: { "_id.building": 1, "_id.level": 1, "_id.room": 1 } }
  ]).toArray();
  return rows.map(({ _id }) => ({ ..._id, key: `${_id.building}/${_id.level}/${_id.room}` }));
}

async function getSeries({ sensorType, minutes, limit, building, level, room }) {
  const query = {};
  if (sensorType && sensorType !== "all") query.sensorType = sensorType;
  if (building) query["location.building"] = building;
  if (level) query["location.level"] = level;
  if (room) query["location.room"] = room;
  if (Number.isFinite(minutes) && minutes > 0) query.receivedAt = { $gte: new Date(Date.now() - minutes * 60000) };
  const cappedLimit = Math.min(Math.max(Number(limit) || 300, 1), 1000);
  const rows = await readings.find(query, { projection: readingProjection }).sort({ receivedAt: -1 }).limit(cappedLimit).toArray();
  return rows.reverse();
}

async function getRecentReadings(limit = 30) {
  return readings.find({}, { projection: readingProjection }).sort({ receivedAt: -1 }).limit(limit).toArray();
}

async function getParkingReadings() {
  return readings.aggregate([
    { $match: { sensorType: "occupancy", "location.building": { $regex: /^carpark-/ } } },
    { $sort: { receivedAt: -1 } },
    { $group: { _id: { building: "$location.building", level: "$location.level", room: "$location.room" }, reading: { $first: "$$ROOT" } } },
    { $replaceRoot: { newRoot: "$reading" } },
    { $sort: { "location.room": 1 } },
    { $project: readingProjection }
  ]).toArray();
}

function broadcast(eventName, data) {
  const frame = `event: ${eventName}\ndata: ${JSON.stringify(data)}\n\n`;
  for (const res of sseClients) res.write(frame);
}

app.get("/api/health", async (req, res) => {
  const documentCount = readings ? await readings.estimatedDocumentCount() : 0;
  res.json({ ok: true, service: "iot-operations-console", runtime, uiMode,
    database: { name: config.mongodbDb, collection: config.mongodbCollection, documentCount },
    mqtt: { brokerUrl: config.mqttBrokerUrl, subscribedTopic: config.mqttSubscribeTopic, uiControlTopic: config.uiControlTopic } });
});
app.get("/api/sensor-types", async (req, res, next) => { try { res.json({ ok: true, data: await getSensorTypes() }); } catch (e) { next(e); } });
app.get("/api/rooms", async (req, res, next) => { try { res.json({ ok: true, data: await getRooms() }); } catch (e) { next(e); } });
app.get("/api/readings/latest", async (req, res, next) => { try { res.json({ ok: true, data: await getLatestReadings() }); } catch (e) { next(e); } });
app.get("/api/readings/recent", async (req, res, next) => { try { res.json({ ok: true, data: await getRecentReadings(Math.min(Number(req.query.limit || 30), 100)) }); } catch (e) { next(e); } });
app.get("/api/readings/series", async (req, res, next) => {
  try {
    const options = {
      sensorType: req.query.sensorType ? String(req.query.sensorType) : "all",
      minutes: req.query.minutes ? Number(req.query.minutes) : 0,
      limit: req.query.limit ? Number(req.query.limit) : 300,
      building: req.query.building ? String(req.query.building) : "",
      level: req.query.level ? String(req.query.level) : "",
      room: req.query.room ? String(req.query.room) : ""
    };
    res.json({ ok: true, query: options, data: await getSeries(options) });
  } catch (e) { next(e); }
});
app.get("/api/parking/latest", async (req, res, next) => { try { res.json({ ok: true, data: await getParkingReadings() }); } catch (e) { next(e); } });

app.get("/api/stream", async (req, res) => {
  res.setHeader("Content-Type", "text/event-stream");
  res.setHeader("Cache-Control", "no-cache");
  res.setHeader("Connection", "keep-alive");
  res.flushHeaders?.();
  sseClients.add(res);

  async function sendSnapshot() {
    try {
      const payload = {
        ok: true, sentAt: new Date().toISOString(), runtime, uiMode,
        readings: await getLatestReadings(),
        rooms: await getRooms(),
        sensorTypes: await getSensorTypes(),
        parkingReadings: await getParkingReadings()
      };
      res.write(`event: snapshot\ndata: ${JSON.stringify(payload)}\n\n`);
    } catch (error) {
      res.write(`event: stream-error\ndata: ${JSON.stringify({ ok: false, message: error.message })}\n\n`);
    }
  }
  await sendSnapshot();
  const interval = setInterval(sendSnapshot, config.sseIntervalMs);
  req.on("close", () => { clearInterval(interval); sseClients.delete(res); });
});

app.use((req, res) => res.status(404).json({ ok: false, error: { message: `Route not found: ${req.method} ${req.originalUrl}` } }));
app.use((error, req, res, next) => { runtime.lastError = error.message; console.error("[API ERROR]", error); res.status(500).json({ ok: false, error: { message: error.message } }); });

async function startMongo() {
  mongoClient = new MongoClient(config.mongodbUri);
  await mongoClient.connect();
  readings = mongoClient.db(config.mongodbDb).collection(config.mongodbCollection);
  await readings.createIndex({ receivedAt: -1 });
  await readings.createIndex({ sensorType: 1, receivedAt: -1 });
  await readings.createIndex({ "location.building": 1, "location.level": 1, "location.room": 1, sensorType: 1, receivedAt: -1 });
  runtime.mongodbConnected = true;
  console.log(`[MongoDB] Connected to ${config.mongodbUri}/${config.mongodbDb}.${config.mongodbCollection}`);
}

function startMqtt() {
  mqttClient = mqtt.connect(config.mqttBrokerUrl, { clientId: `iot-console-${Math.random().toString(16).slice(2)}`, clean: true, reconnectPeriod: 2000 });
  mqttClient.on("connect", () => {
    runtime.mqttConnected = true;
    console.log(`[MQTT] Connected to ${config.mqttBrokerUrl}`);
    mqttClient.subscribe([config.mqttSubscribeTopic, config.uiControlTopic], { qos: 1 }, (error) => {
      if (error) { runtime.lastError = error.message; console.error("[MQTT SUBSCRIBE ERROR]", error.message); return; }
      console.log(`[MQTT] Telemetry: ${config.mqttSubscribeTopic}`);
      console.log(`[MQTT] UI control: ${config.uiControlTopic}`);
    });
  });
  mqttClient.on("reconnect", () => { runtime.mqttConnected = false; console.log("[MQTT] Reconnecting..."); });
  mqttClient.on("close", () => { runtime.mqttConnected = false; });
  mqttClient.on("message", async (topic, message) => {
    try {
      if (topic === config.uiControlTopic) {
        const requested = message.toString("utf8").trim().toLowerCase();
        if (!["environment", "parking"].includes(requested)) {
          console.log(`[UI] Ignored unsupported mode: ${requested}`);
          return;
        }
        uiMode = requested;
        console.log(`[UI] Mode changed to ${uiMode}`);
        broadcast("ui-mode", { mode: uiMode, sentAt: new Date().toISOString() });
        return;
      }
      await storeReading(topic, message);
    } catch (error) { runtime.lastError = error.message; console.error("[MQTT MESSAGE ERROR]", error.message); }
  });
  mqttClient.on("error", (error) => { runtime.lastError = error.message; console.error("[MQTT ERROR]", error.message); });
}

async function start() {
  await startMongo(); startMqtt();
  app.listen(config.port, () => {
    console.log(`[HTTP] Operations API running at http://localhost:${config.port}`);
    console.log(`[HTTP] Health: http://localhost:${config.port}/api/health`);
  });
}
process.on("SIGINT", async () => { console.log("\nStopping server."); mqttClient?.end(true); await mongoClient?.close(); process.exit(0); });
start().catch((error) => { runtime.lastError = error.message; console.error("[STARTUP ERROR]", error); process.exit(1); });
