# IoT Sensor Simulator (Program 1)

**Copyright (c) 2026 Dr Shuo Ding `<shuoding@outlook.com>`.**
Licensed under the **GNU Affero General Public License v3.0 or later
(AGPL-3.0-or-later)**. Any copy, modification, or distribution must retain this
copyright notice and remain under the AGPL. See the
[../LICENSE](../LICENSE) file.

> **Disclaimer.** Teaching software, provided "as is" without warranty. It is
> designed for a local lab with an unauthenticated MQTT broker. Do not expose
> it to the public internet.

---

## What this program does

This program simulates **three independent IoT sensors** and publishes their
readings to an MQTT broker as JSON messages. It is the **publisher** half of the
lab. It does not know anything about the dashboard; it only talks to the broker.

| Sensor       | MQTT topic suffix | Interval   | Realistic range        |
| ------------ | ----------------- | ---------- | ---------------------- |
| temperature  | `/temperature`    | 5 seconds  | 18 – 27 °C             |
| humidity     | `/humidity`       | 5 seconds  | 35 – 65 %              |
| pressure     | `/pressure`       | 5 seconds  | 995 – 1030 hPa         |

### Realistic values (a "random walk")

Real sensors do not jump around. A room does not leap from 22 °C to 27 °C in one
second. To imitate this, each reading is produced from the previous one plus a
**small random step**, then kept inside a believable range. A gentle pull toward
the middle of the range keeps long runs natural. The result is a smooth curve,
which is exactly what you want to see on the dashboard chart.

## Message format

Each reading is published as a JSON message. For example, on the topic
`latrobe/building-a/level-2/room-204/temperature`:

```json
{
  "deviceId": "room-204-temperature-01",
  "sensorType": "temperature",
  "value": 22.4,
  "unit": "celsius",
  "observedAt": "2026-07-01T10:05:00.000Z",
  "sequence": 1
}
```

## Configuration

Settings live in a `.env` file, created automatically from `.env.example` the
first time you run the program:

```bash
MQTT_BROKER_URL=mqtt://localhost:1883
BASE_TOPIC=latrobe/building-a/level-2/room-204
DEVICE_PREFIX=room-204
QOS=1
```

- `MQTT_BROKER_URL` — where the broker is. For this lab it is local.
- `BASE_TOPIC` — the topic prefix. Each sensor type is added to the end, e.g.
  `.../room-204/temperature`.
- `DEVICE_PREFIX` — used to build each device id, e.g. `room-204-temperature-01`.
- `QOS` — MQTT quality of service. `1` means "deliver at least once".

## How to run

Make sure the Mosquitto broker is running first
(`../setup_ubuntu_services.sh`), then:

```bash
chmod +x run_ubuntu.sh
./run_ubuntu.sh
```

The script creates `.env` if needed, installs dependencies (`mqtt`, `dotenv`),
and starts publishing. You will see one log line per published reading. Press
**Ctrl + C** to stop; the program disconnects from the broker cleanly.

## Files

| File                   | Purpose                                                 |
| ---------------------- | ------------------------------------------------------- |
| `sensor-publisher.js`  | The program: builds and publishes readings over MQTT.   |
| `run_ubuntu.sh`        | Convenience script: sets up `.env`, installs, runs.     |
| `.env.example`         | Template for your local `.env` settings.                |
| `package.json`         | Dependencies (`mqtt`, `dotenv`) and the `start` script. |
