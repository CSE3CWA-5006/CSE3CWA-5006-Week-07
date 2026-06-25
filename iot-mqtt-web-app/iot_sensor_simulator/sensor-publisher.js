/*
 * Week 7 IoT Sensor Simulator - sensor-publisher.js
 * Copyright (c) 2026 Dr Shuo Ding <shuoding@outlook.com>
 * Licensed under the GNU Affero General Public License v3.0 or later
 * (AGPL-3.0-or-later). Any copy, modification, or distribution must retain
 * this copyright notice and remain under the AGPL. See the LICENSE file.
 *
 * Purpose: simulate three independent IoT sensors (temperature, humidity,
 * pressure) and publish their readings to an MQTT broker as JSON messages.
 * Each sensor uses a "random walk" so the values drift smoothly and stay
 * inside realistic bounds, instead of jumping randomly between readings.
 */

import "dotenv/config";
import mqtt from "mqtt";

// ---------------------------------------------------------------------------
// Configuration (read from environment, with safe defaults for the lab).
// ---------------------------------------------------------------------------
const brokerUrl = process.env.MQTT_BROKER_URL || "mqtt://localhost:1883";
const baseTopic = process.env.BASE_TOPIC || "latrobe/building-a/level-2/room-204";
const devicePrefix = process.env.DEVICE_PREFIX || "room-204";
const qos = Number(process.env.QOS || 1);

let sequence = 0;

// ---------------------------------------------------------------------------
// Realistic value generation.
//
// Real environmental sensors do not jump around. The temperature in a room
// drifts up or down slowly; it does not leap from 22 C to 27 C in one second.
// We model this with a "random walk":
//
//   nextValue = currentValue + smallRandomStep
//
// The step is small and can be positive or negative, so the value wanders
// gently. We also "clamp" the value so it never leaves a believable range,
// and we add a very small pull back toward a central value so a sensor that
// drifts to the edge of its range tends to ease back toward the middle.
// ---------------------------------------------------------------------------

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function round(value) {
  return Math.round(value * 10) / 10;
}

/**
 * Create a smooth value generator for one sensor.
 *
 * @param {object} options
 * @param {number} options.start    Starting value.
 * @param {number} options.min      Lowest believable value.
 * @param {number} options.max      Highest believable value.
 * @param {number} options.maxStep  Largest change allowed between readings.
 */
function createSmoothValue({ start, min, max, maxStep }) {
  let current = start;
  const centre = (min + max) / 2;

  return function nextValue() {
    // A random step in the range [-maxStep, +maxStep].
    const step = (Math.random() * 2 - 1) * maxStep;

    // A gentle pull back toward the centre keeps long runs realistic.
    const pullToCentre = (centre - current) * 0.02;

    current = clamp(current + step + pullToCentre, min, max);
    return round(current);
  };
}

// ---------------------------------------------------------------------------
// Sensor definitions.
//
// Each sensor publishes on its own interval. In this lab all three use a
// steady 5-second interval, which is a good balance: frequent enough to see
// the dashboard move, slow enough to read the logs. The first publish of each
// sensor is staggered slightly so the three streams do not all fire together.
// ---------------------------------------------------------------------------
const sensors = [
  {
    sensorType: "temperature",
    deviceId: `${devicePrefix}-temperature-01`,
    unit: "celsius",
    intervalMs: 5000,
    // Comfortable indoor room temperature, drifting at most 0.3 C per reading.
    nextValue: createSmoothValue({ start: 22.5, min: 18, max: 27, maxStep: 0.3 })
  },
  {
    sensorType: "humidity",
    deviceId: `${devicePrefix}-humidity-01`,
    unit: "percent",
    intervalMs: 5000,
    // Indoor relative humidity, drifting at most 0.8 percent per reading.
    nextValue: createSmoothValue({ start: 50, min: 35, max: 65, maxStep: 0.8 })
  },
  {
    sensorType: "pressure",
    deviceId: `${devicePrefix}-pressure-01`,
    unit: "hPa",
    intervalMs: 5000,
    // Sea-level atmospheric pressure, drifting at most 0.4 hPa per reading.
    nextValue: createSmoothValue({ start: 1013, min: 995, max: 1030, maxStep: 0.4 })
  }
];

// ---------------------------------------------------------------------------
// Build one MQTT message payload for a sensor reading.
// ---------------------------------------------------------------------------
function buildPayload(sensor) {
  sequence += 1;

  return {
    deviceId: sensor.deviceId,
    sensorType: sensor.sensorType,
    value: sensor.nextValue(),
    unit: sensor.unit,
    observedAt: new Date().toISOString(),
    sequence
  };
}

// ---------------------------------------------------------------------------
// Connect to the MQTT broker and start publishing.
// ---------------------------------------------------------------------------
const client = mqtt.connect(brokerUrl, {
  clientId: `week7-sensor-simulator-${Math.random().toString(16).slice(2)}`,
  clean: true,
  reconnectPeriod: 2000
});

client.on("connect", () => {
  console.log(`[MQTT] Connected to ${brokerUrl}`);
  console.log("[MQTT] Publishing one reading per sensor every 5 seconds.");
  console.log("");

  sensors.forEach((sensor, index) => {
    const topic = `${baseTopic}/${sensor.sensorType}`;

    const publishReading = () => {
      const payload = buildPayload(sensor);
      const message = JSON.stringify(payload);

      client.publish(topic, message, { qos }, (error) => {
        if (error) {
          console.error(`[PUBLISH ERROR] ${topic}`, error.message);
          return;
        }

        console.log(`[PUBLISH] ${topic}`);
        console.log(message);
      });
    };

    // Stagger the very first publish of each sensor by a small amount so the
    // three streams do not all fire on the same tick. After that, each sensor
    // publishes on its own steady interval.
    setTimeout(() => {
      publishReading();
      setInterval(publishReading, sensor.intervalMs);
    }, index * 1500);
  });
});

client.on("reconnect", () => {
  console.log("[MQTT] Reconnecting to broker...");
});

client.on("error", (error) => {
  console.error("[MQTT ERROR]", error.message);
});

// Stop cleanly when the user presses Ctrl + C.
process.on("SIGINT", () => {
  console.log("");
  console.log("Stopping sensor simulator.");
  client.end(true, () => process.exit(0));
});
