# IoT MQTT Dashboard (Program 2)

**Copyright (c) 2026 Dr Shuo Ding `<shuoding@outlook.com>`.**
Licensed under the **GNU Affero General Public License v3.0 or later
(AGPL-3.0-or-later)**. Any copy, modification, or distribution must retain this
copyright notice and remain under the AGPL. See the
[../LICENSE](../LICENSE) file.

> **Disclaimer.** Teaching software, provided "as is" without warranty. It is
> designed for a local lab with an unauthenticated MQTT broker and MongoDB
> instance. Do not expose these services to the public internet.

---

## What this program does

This is the **subscriber** half of the lab. It has two parts that run together:

1. **`server/`** — an **Express** backend that:
   - connects to the MQTT broker and **subscribes** to the sensor topics,
   - **validates** each message and **stores** it as a document in **MongoDB**,
   - exposes a small **HTTP API** and a live **Server-Sent Events** stream.
2. **`client/`** — a **React** frontend that:
   - opens the event stream and updates on its own every few seconds,
   - shows the latest value of each sensor, a **real-time line chart**, and a
     table,
   - lets you **filter** by sensor type and choose a **time window**.

The frontend never connects to MQTT or MongoDB directly. It only talks to the
backend. This keeps infrastructure details out of the browser.

## Architecture

```
MQTT broker --message--> Express backend --insert--> MongoDB
                              |                          |
                              |  every few seconds: query latest + history
                              v                          |
                        SSE /api/stream <----------------+
                              |
                              v
                        React frontend (charts, filters, table)
```

## How to run

Make sure Mosquitto and MongoDB are running first
(`../setup_ubuntu_services.sh`), then:

```bash
chmod +x run_ubuntu.sh
./run_ubuntu.sh
```

This starts the backend on `http://localhost:4100` and the frontend on
`http://localhost:5174`. Open the frontend in your browser:

```
http://localhost:5174
```

Start the sensor simulator in another terminal so data begins to flow.

## Configuration

### Backend — `server/.env` (from `server/.env.example`)

```bash
PORT=4100
FRONTEND_ORIGIN=http://localhost:5174
MQTT_BROKER_URL=mqtt://localhost:1883
MQTT_SUBSCRIBE_TOPIC=latrobe/+/+/+/+
MONGODB_URI=mongodb://127.0.0.1:27017
MONGODB_DB=week7_iot
MONGODB_COLLECTION=sensor_readings
SSE_INTERVAL_MS=5000
```

The `+` in the subscribe topic is the MQTT single-level wildcard. The filter
`latrobe/+/+/+/+` matches any campus/building/level/room/sensor path.

### Frontend — `client/.env` (from `client/.env.example`)

```bash
VITE_API_BASE=http://localhost:4100
```

This tells the React app where the backend is.

## API endpoints

| Method & path                                            | Returns                                          |
| -------------------------------------------------------- | ------------------------------------------------ |
| `GET /api/health`                                        | MQTT/MongoDB status, counters, collection info.  |
| `GET /api/sensor-types`                                  | The distinct sensor types in the database.       |
| `GET /api/readings/latest`                               | Latest reading for each sensor type.             |
| `GET /api/readings/recent?limit=N`                       | Most recent N readings (max 100).                |
| `GET /api/readings/series?sensorType=...&minutes=...`    | Time-ordered history for charts.                 |
| `GET /api/stream`                                        | Server-Sent Events snapshot stream.              |

## MongoDB document shape

Every MQTT message becomes one document in `week7_iot.sensor_readings`:

```json
{
  "topic": "latrobe/building-a/level-2/room-204/temperature",
  "deviceId": "room-204-temperature-01",
  "sensorType": "temperature",
  "value": 22.4,
  "unit": "celsius",
  "observedAt": "2026-07-01T10:05:00.000Z",
  "receivedAt": "2026-07-01T10:05:01.280Z",
  "sequence": 1,
  "location": {
    "campus": "latrobe",
    "building": "building-a",
    "level": "level-2",
    "room": "room-204"
  },
  "rawPayload": { "...": "the original message" }
}
```

`observedAt` is when the sensor says it measured the value. `receivedAt` is when
the backend stored it. In real systems these can differ due to network delay.

## Files

| File                          | Purpose                                                |
| ----------------------------- | ------------------------------------------------------ |
| `server/src/server.js`        | Express backend: MQTT subscribe, MongoDB store, API.   |
| `client/src/main.jsx`         | React app: stream client, chart, filters, table.       |
| `client/src/styles.css`       | Dashboard styling.                                     |
| `client/index.html`           | HTML entry point loaded by Vite.                       |
| `client/vite.config.js`       | Vite dev-server configuration (port 5174).             |
| `run_ubuntu.sh`               | Starts backend and frontend together.                  |
