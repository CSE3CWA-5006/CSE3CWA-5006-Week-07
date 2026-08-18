# Smart City IoT Operations Console

A local teaching and demonstration platform for **MQTT telemetry, MongoDB persistence, Server-Sent Events (SSE), and React-based operational views**.

**Copyright © 2026 Dr Shuo Ding `<shuoding@outlook.com>`**  
Licensed under the **GNU Affero General Public License v3.0 or later (AGPL-3.0-or-later)**. See [`LICENSE`](./LICENSE) for the full licence terms.

> **Local-lab security notice:** the supplied configuration is intentionally designed for a local, single-machine workshop. Mosquitto and MongoDB are used locally without production authentication/TLS hardening. Do not expose these services directly to the public Internet. A production deployment should add authentication, TLS, access control, monitoring, backup and retention policies.

---

## Overview

The project provides one reusable IoT platform with two operational views:

- **Environmental Monitoring** — temperature, humidity and pressure, with automatic multi-room discovery and room-specific history.
- **Smart Parking** — six default parking bays with live FREE/OCCUPIED state and summary cards.

The same backend, MongoDB database, MQTT broker, SSE connection and React application are reused across both views.

```text
IoT publishers
     |
     | MQTT QoS 1
     v
Mosquitto broker :1883
     |
     v
Node / Express backend :4100
     |
     +----> MongoDB :27017
     |
     +----> HTTP API
     |
     +----> Server-Sent Events (SSE)
                  |
                  v
          React / Vite :5174
                  |
          +-------+-------+
          |               |
   Environment       Smart Parking
```

The browser does **not** subscribe directly to MQTT. MQTT terminates at the backend; the browser receives application updates through SSE and uses HTTP APIs for historical series queries.

---

## Project structure

```text
iot-mqtt-web-app/
├── LICENSE
├── README.md
├── setup_ubuntu_services.sh
├── iot_sensor_simulator/
│   ├── .env.example
│   ├── sensor-publisher.js
│   ├── run_ubuntu.sh
│   └── README.md
└── iot_mqtt_dashboard/
    ├── run_ubuntu.sh
    ├── server/
    │   ├── .env.example
    │   └── src/server.js
    ├── client/
    │   ├── .env.example
    │   └── src/
    │       ├── main.jsx
    │       └── styles.css
    └── README.md
```

### Main components

| Component | Purpose |
| --- | --- |
| `iot_sensor_simulator` | Publishes simulated Room 204 temperature, humidity and pressure readings every five seconds. |
| Mosquitto | Local MQTT broker used by publishers and the backend subscriber. |
| Dashboard backend | Subscribes to telemetry/control topics, validates telemetry, stores readings in MongoDB, exposes APIs and publishes SSE updates. |
| MongoDB | Persists telemetry in `week7_iot.sensor_readings`. |
| React frontend | Provides the Smart City IoT Operations Console, room filtering, charts and Smart Parking view. |

---

## Requirements

For the supplied Ubuntu workflow:

- Ubuntu 20.04, 22.04 or 24.04 LTS
- **Node.js 24** and npm
- Internet access for the initial package installation

The workshop uses NVM to install Node.js 24:

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.6/install.sh | bash
\. "$HOME/.nvm/nvm.sh"
nvm install 24
nvm use 24
node -v
npm -v
```

### macOS

`setup_ubuntu_services.sh` is Ubuntu-specific. On macOS, install MongoDB and Mosquitto separately, then use the same Node applications and local service addresses expected by the `.env.example` files.

---

## Install local services on Ubuntu

From `iot-mqtt-web-app/`:

```bash
chmod +x setup_ubuntu_services.sh
./setup_ubuntu_services.sh
```

The script installs/configures the local workshop services, including:

- Mosquitto
- `mosquitto_pub` and `mosquitto_sub`
- MongoDB Community Edition 8.0 when required
- service startup and basic connectivity checks

Check the services with:

```bash
systemctl is-active mosquitto
systemctl is-active mongod
```

Both should report `active`.

---

## Run the platform

### 1. Start the dashboard

From `iot-mqtt-web-app/`:

```bash
cd iot_mqtt_dashboard
chmod +x run_ubuntu.sh
./run_ubuntu.sh
```

Open:

```text
http://localhost:5174
```

The backend runs at:

```text
http://localhost:4100
```

### 2. Start the environmental sensor simulator

In another terminal, from `iot-mqtt-web-app/`:

```bash
cd iot_sensor_simulator
chmod +x run_ubuntu.sh
./run_ubuntu.sh
```

The supplied simulator publishes Room 204 telemetry every five seconds using MQTT QoS 1.

---

## MQTT topic model

Telemetry uses a five-level structure:

```text
latrobe/<building>/<level>/<room>/<sensorType>
```

Examples:

```text
latrobe/building-a/level-2/room-204/temperature
latrobe/building-a/level-2/room-204/humidity
latrobe/building-a/level-2/room-204/pressure
latrobe/building-a/level-2/room-205/temperature
latrobe/carpark-a/level-1/bay-01/occupancy
```

The backend telemetry subscription is:

```text
latrobe/+/+/+/+
```

Each `+` matches exactly one MQTT topic level.

The backend also subscribes to the UI control topic:

```text
latrobe/ui/mode
```

Supported control payloads are:

```text
environment
parking
```

Unsupported UI modes are ignored.

---

## Telemetry payload

A normal reading is JSON. For example:

```json
{
  "deviceId": "room-204-temperature-01",
  "sensorType": "temperature",
  "value": 23.4,
  "unit": "celsius",
  "observedAt": "2026-08-19T00:00:00.000Z",
  "sequence": 1
}
```

The backend parses the MQTT topic into location fields and stores accepted readings with information including:

- `topic`
- `deviceId`
- `sensorType`
- `value`
- `unit`
- `observedAt`
- `receivedAt`
- `sequence`
- `location.campus`
- `location.building`
- `location.level`
- `location.room`
- `rawPayload`

The backend rejects readings that do not contain a usable device ID/sensor type, a finite numeric value, and a valid observation time.

---

## Environmental Monitoring

The supplied simulator publishes:

| Sensor | Topic | Unit |
| --- | --- | --- |
| Temperature | `latrobe/building-a/level-2/room-204/temperature` | `celsius` |
| Humidity | `latrobe/building-a/level-2/room-204/humidity` | `percent` |
| Pressure | `latrobe/building-a/level-2/room-204/pressure` | `hPa` |

### Automatic multi-room support

Rooms are **not hard-coded into the React room selector**. A room becomes available after valid non-parking telemetry for that `building / level / room` exists in MongoDB.

For example, create Room 205 without changing source code:

```bash
mosquitto_pub -h localhost -q 1 \
  -t "latrobe/building-a/level-2/room-205/temperature" \
  -m "{\"deviceId\":\"room-205-temperature-01\",\"sensorType\":\"temperature\",\"value\":28.5,\"unit\":\"celsius\",\"observedAt\":\"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\",\"sequence\":1}"
```

The Environment view can then expose Room 205 in the **Room** selector. Current readings are kept separate by building, level, room and sensor type. Historical series requests can also be filtered by location.

Example room-specific series request:

```bash
curl "http://localhost:4100/api/readings/series?sensorType=temperature&building=building-a&level=level-2&room=room-205&minutes=5"
```

---

## Smart Parking

Switch the running application to the Smart Parking view:

```bash
mosquitto_pub -h localhost -q 1 \
  -t "latrobe/ui/mode" \
  -m "parking"
```

Switch back to Environmental Monitoring:

```bash
mosquitto_pub -h localhost -q 1 \
  -t "latrobe/ui/mode" \
  -m "environment"
```

Changing the active view does **not** delete telemetry from MongoDB.

### Parking occupancy telemetry

Parking uses the same five-level telemetry structure:

```text
latrobe/carpark-a/level-1/bay-01/occupancy
```

For the workshop parking model:

- `value: 0` = **FREE**
- `value: 1` = **OCCUPIED**

Example — mark Bay 01 occupied:

```bash
mosquitto_pub -h localhost -q 1 \
  -t "latrobe/carpark-a/level-1/bay-01/occupancy" \
  -m "{\"deviceId\":\"bay-01-sensor\",\"sensorType\":\"occupancy\",\"value\":1,\"unit\":\"boolean\",\"observedAt\":\"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\",\"sequence\":1}"
```

Example — mark Bay 01 free:

```bash
mosquitto_pub -h localhost -q 1 \
  -t "latrobe/carpark-a/level-1/bay-01/occupancy" \
  -m "{\"deviceId\":\"bay-01-sensor\",\"sensorType\":\"occupancy\",\"value\":0,\"unit\":\"boolean\",\"observedAt\":\"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\",\"sequence\":2}"
```

The UI contains six default bays (Bay 01–06). When there is no stored parking reading for a default bay, the workshop UI displays it as **FREE**. Stored occupancy readings override that default. The summary cards show **Total Bays**, **Free**, and **Occupied**.

Parking telemetry is persisted in the same MongoDB collection as other telemetry. Parking readings are identified by `sensorType: "occupancy"` and a `location.building` beginning with `carpark-`.

---

## Live update behaviour

The backend exposes an SSE endpoint at:

```text
http://localhost:4100/api/stream
```

The stream provides an initial snapshot and regular snapshots. It also emits targeted live events used by the UI:

- `ui-mode` — changes the active Environment/Parking view.
- `parking-data` — updates Smart Parking when a valid parking reading is stored.

The frontend uses the HTTP series API when it needs room/sensor-specific chart history.

---

## HTTP API

| Endpoint | Purpose |
| --- | --- |
| `GET /api/health` | Runtime state, MQTT/MongoDB status, database information and configured MQTT topics. |
| `GET /api/rooms` | Distinct non-parking locations available to the Environment room selector. |
| `GET /api/sensor-types` | Distinct non-parking sensor types. |
| `GET /api/readings/latest` | Latest reading per building + level + room + sensor type. |
| `GET /api/readings/recent?limit=20` | Most recently stored readings. Maximum requested limit is capped by the backend. |
| `GET /api/readings/series?...` | Time-ordered history, optionally filtered by sensor type, building, level, room and time window. |
| `GET /api/parking/latest` | Latest stored occupancy reading for each discovered parking bay. |
| `GET /api/stream` | SSE stream used by the React application. |

Example:

```bash
curl http://localhost:4100/api/health
curl http://localhost:4100/api/rooms
curl http://localhost:4100/api/readings/latest
curl "http://localhost:4100/api/readings/recent?limit=20"
curl "http://localhost:4100/api/readings/series?sensorType=temperature&building=building-a&level=level-2&room=room-204&minutes=5"
curl http://localhost:4100/api/parking/latest
```

---

## MongoDB

Default configuration:

```text
URI:        mongodb://127.0.0.1:27017
Database:   week7_iot
Collection: sensor_readings
```

Inspect recent readings:

```bash
mongosh
```

```javascript
use week7_iot
db.sensor_readings.find().sort({ receivedAt: -1 }).limit(10)
```

Inspect one environmental room:

```javascript
db.sensor_readings.find({
  "location.building": "building-a",
  "location.level": "level-2",
  "location.room": "room-205"
}).sort({ receivedAt: -1 }).limit(10)
```

Inspect parking telemetry:

```javascript
db.sensor_readings.find({
  "location.building": "carpark-a",
  sensorType: "occupancy"
}).sort({ receivedAt: -1 }).limit(10)
```

To remove the local workshop database and start with no stored telemetry:

```javascript
use week7_iot
db.dropDatabase()
```

Stop publishers first if you want the database to remain empty after dropping it.

---

## Ports and default local addresses

| Service | Default address |
| --- | --- |
| Mosquitto | `mqtt://localhost:1883` |
| MongoDB | `mongodb://127.0.0.1:27017` |
| Node/Express API | `http://localhost:4100` |
| React/Vite UI | `http://localhost:5174` |

---

## Configuration

### Dashboard backend — `iot_mqtt_dashboard/server/.env`

Created from `.env.example` on first run. Defaults include:

```text
PORT=4100
FRONTEND_ORIGIN=http://localhost:5174
MQTT_BROKER_URL=mqtt://localhost:1883
MQTT_SUBSCRIBE_TOPIC=latrobe/+/+/+/+
MONGODB_URI=mongodb://127.0.0.1:27017
MONGODB_DB=week7_iot
MONGODB_COLLECTION=sensor_readings
SSE_INTERVAL_MS=5000
```

The UI control topic `latrobe/ui/mode` is defined by the backend application.

### Sensor simulator — `iot_sensor_simulator/.env`

```text
MQTT_BROKER_URL=mqtt://localhost:1883
BASE_TOPIC=latrobe/building-a/level-2/room-204
DEVICE_PREFIX=room-204
QOS=1
```

---

## Quick MQTT inspection

Watch all five-level telemetry handled by the backend:

```bash
mosquitto_sub -h localhost -q 1 -t "latrobe/+/+/+/+" -v
```

Watch one exact topic:

```bash
mosquitto_sub -h localhost -q 1 \
  -t "latrobe/building-a/level-2/room-204/temperature" -v
```

---

## Design notes and workshop assumptions

- The application currently models location to the **room/bay level** through the five-level MQTT topic structure.
- Environmental rooms are discovered from stored non-occupancy telemetry rather than a hard-coded room list.
- The Environment view filters current readings and chart history by the selected room.
- Smart Parking provides six default bays for the workshop UI. Additional stored parking bay identifiers can also be represented by the parking data model/UI logic.
- A default FREE bay with no stored telemetry is a **workshop display assumption**, not proof from a physical parking sensor. A production system would normally distinguish unknown/offline state from confirmed free state.
- UI mode is presentation/application state; switching modes does not remove stored telemetry.
- This project is intentionally local and educational rather than a production deployment template.

---

## Licence and copyright

**Copyright © 2026 Dr Shuo Ding `<shuoding@outlook.com>`**

This project is free software licensed under the **GNU Affero General Public License v3.0 or later (AGPL-3.0-or-later)**.

You may use, study, modify and redistribute the software under the terms of the AGPL. If you modify the program and make the modified version available to users over a network, the AGPL includes source-code obligations for those users. See the included [`LICENSE`](./LICENSE) file for the complete legal terms.

When redistributing this project or modified versions, retain the applicable copyright and licence notices.

This software is provided **without warranty**, to the extent permitted by applicable law. Refer to the AGPL text for the governing warranty and liability terms.

---

## Additional documentation

- [`iot_sensor_simulator/README.md`](./iot_sensor_simulator/README.md)
- [`iot_mqtt_dashboard/README.md`](./iot_mqtt_dashboard/README.md)
- [`LICENSE`](./LICENSE)
