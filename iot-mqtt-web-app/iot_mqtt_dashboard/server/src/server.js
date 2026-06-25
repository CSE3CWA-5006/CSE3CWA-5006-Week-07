/*
 * Week 7 IoT MQTT Dashboard - server.js (Express backend)
 * Copyright (c) 2026 Dr Shuo Ding <shuoding@outlook.com>
 * Licensed under the GNU Affero General Public License v3.0 or later
 * (AGPL-3.0-or-later). Any copy, modification, or distribution must retain
 * this copyright notice and remain under the AGPL. See the LICENSE file.
 *
 * Purpose: subscribe to MQTT sensor topics, validate and store each reading
 * as a MongoDB document, and expose HTTP endpoints (including a Server-Sent
 * Events stream) that the React dashboard uses to show live and historical
 * data.
 */

import "dotenv/config";
import cors from "cors";
import express from "express";
import morgan from "morgan";
import mqtt from "mqtt";
import { MongoClient } from "mongodb";

// ---------------------------------------------------------------------------
// Configuration (environment first, then safe local defaults).
// ---------------------------------------------------------------------------
const config = {
  port: Number(process.env.PORT || 4100),
  frontendOrigin: process.env.FRONTEND_ORIGIN || "http://localhost:5174",
  mqttBrokerUrl: process.env.MQTT_BROKER_URL || "mqtt://localhost:1883",
  mqttSubscribeTopic: process.env.MQTT_SUBSCRIBE_TOPIC || "latrobe/+/+/+/+",
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

// Small runtime object so the dashboard can show live system health.
const runtime = {
  mqttConnected: false,
  mongodbConnected: false,
  receivedMessages: 0,
  storedMessages: 0,
  lastMessageAt: null,
  lastError: null
};

// ---------------------------------------------------------------------------
// Helpers: parse the MQTT payload and topic into a clean MongoDB document.
// ---------------------------------------------------------------------------
function parseJsonPayload(buffer) {
  try {
    return JSON.parse(buffer.toString("utf8"));
  } catch (error) {
    throw new Error(`Invalid JSON payload: ${error.message}`);
  }
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
  const observedAt = payload.observedAt ? new Date(payload.observedAt) : new Date();
  const receivedAt = new Date();

  return {
    topic,
    deviceId: String(payload.deviceId || "unknown-device"),
    sensorType: String(payload.sensorType || topicInfo.sensorType),
    value: Number(payload.value),
    unit: String(payload.unit || ""),
    observedAt,
    receivedAt,
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
  return (
    reading.deviceId !== "unknown-device" &&
    reading.sensorType !== "unknown" &&
    Number.isFinite(reading.value) &&
    reading.observedAt instanceof Date &&
    !Number.isNaN(reading.observedAt.getTime())
  );
}

// ---------------------------------------------------------------------------
// Store one reading. Called for every MQTT message that arrives.
// ---------------------------------------------------------------------------
async function storeReading(topic, message) {
  runtime.receivedMessages += 1;
  runtime.lastMessageAt = new Date().toISOString();

  const payload = parseJsonPayload(message);
  const reading = normaliseReading(topic, payload);

  if (!isValidReading(reading)) {
    throw new Error(`Rejected invalid reading from topic ${topic}`);
  }

  await readings.insertOne(reading);
  runtime.storedMessages += 1;

  console.log(`[STORE] ${reading.sensorType} ${reading.value} ${reading.unit} from ${reading.deviceId}`);
}

// Shared projection so every endpoint returns the same clean shape.
const readingProjection = {
  _id: 0,
  topic: 1,
  deviceId: 1,
  sensorType: 1,
  value: 1,
  unit: 1,
  observedAt: 1,
  receivedAt: 1,
  sequence: 1,
  location: 1
};

// Latest reading for each distinct sensor type.
async function getLatestReadings() {
  return readings
    .aggregate([
      { $sort: { receivedAt: -1 } },
      { $group: { _id: "$sensorType", reading: { $first: "$$ROOT" } } },
      { $replaceRoot: { newRoot: "$reading" } },
      { $sort: { sensorType: 1 } },
      { $project: readingProjection }
    ])
    .toArray();
}

// The list of distinct sensor types that exist in the database (for filters).
async function getSensorTypes() {
  const types = await readings.distinct("sensorType");
  return types.sort();
}

/**
 * Time-ordered history used to draw the dashboard line charts.
 *
 * @param {object} options
 * @param {string} [options.sensorType] Only this sensor type, or all if omitted.
 * @param {number} [options.minutes]    Only readings from the last N minutes.
 * @param {number} [options.limit]      Maximum number of points per request.
 */
async function getSeries({ sensorType, minutes, limit }) {
  const query = {};

  if (sensorType && sensorType !== "all") {
    query.sensorType = sensorType;
  }

  if (Number.isFinite(minutes) && minutes > 0) {
    const since = new Date(Date.now() - minutes * 60 * 1000);
    query.receivedAt = { $gte: since };
  }

  const cappedLimit = Math.min(Math.max(Number(limit) || 200, 1), 1000);

  // Read newest-first (fast with our index), then flip to oldest-first so the
  // charts draw left-to-right in time order.
  const rows = await readings
    .find(query, { projection: readingProjection })
    .sort({ receivedAt: -1 })
    .limit(cappedLimit)
    .toArray();

  return rows.reverse();
}

async function getRecentReadings(limit = 30) {
  return readings
    .find({}, { projection: readingProjection })
    .sort({ receivedAt: -1 })
    .limit(limit)
    .toArray();
}

// ---------------------------------------------------------------------------
// HTTP endpoints.
// ---------------------------------------------------------------------------
app.get("/api/health", async (req, res) => {
  const documentCount = readings ? await readings.estimatedDocumentCount() : 0;

  res.json({
    ok: true,
    service: "iot-mqtt-dashboard-server",
    runtime,
    database: {
      name: config.mongodbDb,
      collection: config.mongodbCollection,
      documentCount
    },
    mqtt: {
      brokerUrl: config.mqttBrokerUrl,
      subscribedTopic: config.mqttSubscribeTopic
    }
  });
});

app.get("/api/sensor-types", async (req, res, next) => {
  try {
    res.json({ ok: true, data: await getSensorTypes() });
  } catch (error) {
    next(error);
  }
});

app.get("/api/readings/latest", async (req, res, next) => {
  try {
    res.json({ ok: true, data: await getLatestReadings() });
  } catch (error) {
    next(error);
  }
});

app.get("/api/readings/recent", async (req, res, next) => {
  try {
    const limit = Math.min(Number(req.query.limit || 30), 100);
    res.json({ ok: true, data: await getRecentReadings(limit) });
  } catch (error) {
    next(error);
  }
});

app.get("/api/readings/series", async (req, res, next) => {
  try {
    const sensorType = req.query.sensorType ? String(req.query.sensorType) : "all";
    const minutes = req.query.minutes ? Number(req.query.minutes) : 0;
    const limit = req.query.limit ? Number(req.query.limit) : 200;

    res.json({
      ok: true,
      query: { sensorType, minutes, limit },
      data: await getSeries({ sensorType, minutes, limit })
    });
  } catch (error) {
    next(error);
  }
});

// Server-Sent Events: push a fresh snapshot (latest + recent history) to the
// browser on a steady interval, so the dashboard updates without polling.
app.get("/api/stream", async (req, res) => {
  res.setHeader("Content-Type", "text/event-stream");
  res.setHeader("Cache-Control", "no-cache");
  res.setHeader("Connection", "keep-alive");
  res.flushHeaders?.();

  async function sendSnapshot() {
    try {
      const payload = {
        ok: true,
        sentAt: new Date().toISOString(),
        runtime,
        readings: await getLatestReadings(),
        sensorTypes: await getSensorTypes(),
        series: await getSeries({ sensorType: "all", minutes: 0, limit: 300 })
      };
      res.write(`event: snapshot\n`);
      res.write(`data: ${JSON.stringify(payload)}\n\n`);
    } catch (error) {
      res.write(`event: stream-error\n`);
      res.write(`data: ${JSON.stringify({ ok: false, message: error.message })}\n\n`);
    }
  }

  await sendSnapshot();
  const interval = setInterval(sendSnapshot, config.sseIntervalMs);

  req.on("close", () => {
    clearInterval(interval);
  });
});

// 404 handler.
app.use((req, res) => {
  res.status(404).json({
    ok: false,
    error: { message: `Route not found: ${req.method} ${req.originalUrl}` }
  });
});

// Central error handler.
app.use((error, req, res, next) => {
  runtime.lastError = error.message;
  console.error("[API ERROR]", error);
  res.status(500).json({ ok: false, error: { message: error.message } });
});

// ---------------------------------------------------------------------------
// Startup: connect to MongoDB, connect to MQTT, then listen for HTTP.
// ---------------------------------------------------------------------------
async function startMongo() {
  mongoClient = new MongoClient(config.mongodbUri);
  await mongoClient.connect();
  readings = mongoClient.db(config.mongodbDb).collection(config.mongodbCollection);
  await readings.createIndex({ receivedAt: -1 });
  await readings.createIndex({ sensorType: 1, receivedAt: -1 });
  await readings.createIndex({ topic: 1, receivedAt: -1 });
  runtime.mongodbConnected = true;
  console.log(`[MongoDB] Connected to ${config.mongodbUri}/${config.mongodbDb}.${config.mongodbCollection}`);
}

function startMqtt() {
  mqttClient = mqtt.connect(config.mqttBrokerUrl, {
    clientId: `week7-dashboard-server-${Math.random().toString(16).slice(2)}`,
    clean: true,
    reconnectPeriod: 2000
  });

  mqttClient.on("connect", () => {
    runtime.mqttConnected = true;
    console.log(`[MQTT] Connected to ${config.mqttBrokerUrl}`);
    mqttClient.subscribe(config.mqttSubscribeTopic, { qos: 1 }, (error) => {
      if (error) {
        runtime.lastError = error.message;
        console.error("[MQTT SUBSCRIBE ERROR]", error.message);
        return;
      }
      console.log(`[MQTT] Subscribed to ${config.mqttSubscribeTopic}`);
    });
  });

  mqttClient.on("reconnect", () => {
    runtime.mqttConnected = false;
    console.log("[MQTT] Reconnecting...");
  });

  mqttClient.on("close", () => {
    runtime.mqttConnected = false;
  });

  mqttClient.on("message", async (topic, message) => {
    try {
      await storeReading(topic, message);
    } catch (error) {
      runtime.lastError = error.message;
      console.error("[MQTT MESSAGE ERROR]", error.message);
    }
  });

  mqttClient.on("error", (error) => {
    runtime.lastError = error.message;
    console.error("[MQTT ERROR]", error.message);
  });
}

async function start() {
  await startMongo();
  startMqtt();

  app.listen(config.port, () => {
    console.log(`[HTTP] API server running at http://localhost:${config.port}`);
    console.log(`[HTTP] Health: http://localhost:${config.port}/api/health`);
    console.log(`[HTTP] Latest readings: http://localhost:${config.port}/api/readings/latest`);
  });
}

process.on("SIGINT", async () => {
  console.log("");
  console.log("Stopping server.");
  mqttClient?.end(true);
  await mongoClient?.close();
  process.exit(0);
});

start().catch((error) => {
  runtime.lastError = error.message;
  console.error("[STARTUP ERROR]", error);
  process.exit(1);
});
