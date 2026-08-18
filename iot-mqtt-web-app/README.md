# Week 7 Page 2 — IoT Data Pipeline (MQTT + MongoDB + React)

**Copyright (c) 2026 Dr Shuo Ding `<shuoding@outlook.com>`.**
Licensed under the **GNU Affero General Public License v3.0 or later
(AGPL-3.0-or-later)**. Any copy, modification, or distribution must retain this
copyright notice and remain under the AGPL. See the [LICENSE](./LICENSE) file
for the full terms.

> **Disclaimer.** This software is provided for teaching purposes only, "as is"
> and without warranty of any kind, express or implied. It is intentionally
> configured for a local, single-machine lab: the MQTT broker and MongoDB run
> without authentication or encryption. **Do not expose these services to the
> public internet.** Production IoT systems require authentication, TLS, access
> control, monitoring and data-retention policies. The author accepts no
> liability for any use of this software.

---

## What this project is

This project is a small but complete **IoT data pipeline** made of two
independent programs that communicate only through an MQTT broker:

1. **`iot_sensor_simulator/`** — pretends to be three IoT sensors
   (temperature, humidity, pressure) and **publishes** readings to MQTT topics.
2. **`iot_mqtt_dashboard/`** — a backend that **subscribes** to those topics,
   stores each reading in **MongoDB**, and a **React** frontend that shows the
   live values, a real-time chart, and a table.

A helper script, **`setup_ubuntu_services.sh`**, installs and starts the two
background services (the **Mosquitto** MQTT broker and **MongoDB**) on Ubuntu.

```
v1/
├── LICENSE                       AGPL-3.0 licence text
├── README.md                     this file
├── setup_ubuntu_services.sh      installs Mosquitto + MongoDB on Ubuntu
├── image/                        diagrams used by the teaching page
├── iot_sensor_simulator/         Program 1: publishes sensor data over MQTT
└── iot_mqtt_dashboard/           Program 2: subscribes, stores, and displays
    ├── server/                   Express backend (MQTT + MongoDB + API)
    └── client/                   React frontend (charts, filters, table)
```

## The big idea: two programs, one broker

The sensor program never calls the dashboard, and the dashboard never asks the
sensors for data. Both connect to the **broker**, and the broker delivers
messages by **topic**. This loose coupling is the core idea of MQTT and of most
real IoT systems: publishers and subscribers do not need to know about each
other.

```
[ sensor simulator ] --publish--> [ Mosquitto broker ] --deliver--> [ dashboard backend ]
                                                                          |
                                                                     stores in
                                                                          v
                                                                     [ MongoDB ]
                                                                          |
                                                          live snapshot (SSE) to
                                                                          v
                                                                  [ React frontend ]
```

## Requirements

- **Ubuntu** 20.04, 22.04 or 24.04 LTS (the setup script targets these).
- **Node.js 20 LTS or newer** and **npm** (used by both programs).
- Internet access the first time, to install packages.

## How to run (three steps, two terminals)

### Step 1 — install the services (once)

```bash
chmod +x setup_ubuntu_services.sh
./setup_ubuntu_services.sh
```

This installs and starts Mosquitto (MQTT broker, port `1883`) and MongoDB
(database, port `27017`). You will be asked for your password because installing
system packages needs `sudo` rights.

### Step 2 — start the dashboard (Terminal 1)

```bash
cd iot_mqtt_dashboard
chmod +x run_ubuntu.sh
./run_ubuntu.sh
```

Then open the dashboard in your browser:

```
http://localhost:5174
```

The dashboard may be empty at first — that is expected until the sensor starts.

### Step 3 — start the sensor simulator (Terminal 2)

```bash
cd iot_sensor_simulator
chmod +x run_ubuntu.sh
./run_ubuntu.sh
```

Within a few seconds the dashboard chart and table begin to update on their own.

## Ports used

| Service / program        | Address                          |
| ------------------------ | -------------------------------- |
| Mosquitto MQTT broker    | `mqtt://localhost:1883`          |
| MongoDB                  | `mongodb://127.0.0.1:27017`      |
| Dashboard backend (API)  | `http://localhost:4100`          |
| Dashboard frontend (web) | `http://localhost:5174`          |

## Useful backend test URLs

| URL                                                              | Purpose                                              |
| ---------------------------------------------------------------- | ---------------------------------------------------- |
| `http://localhost:4100/api/health`                               | MQTT/MongoDB status and message counters.            |
| `http://localhost:4100/api/readings/latest`                      | Latest reading for each sensor type.                 |
| `http://localhost:4100/api/readings/recent?limit=20`             | Most recent stored readings.                         |
| `http://localhost:4100/api/readings/series?sensorType=temperature&minutes=5` | Time-ordered history for the charts.     |
| `http://localhost:4100/api/sensor-types`                         | Distinct sensor types in the database.               |
| `http://localhost:4100/api/stream`                               | Server-Sent Events stream used by the React page.    |

## See also

- [`iot_sensor_simulator/README.md`](./iot_sensor_simulator/README.md) — the publisher in detail.
- [`iot_mqtt_dashboard/README.md`](./iot_mqtt_dashboard/README.md) — the subscriber, database and web UI in detail.
