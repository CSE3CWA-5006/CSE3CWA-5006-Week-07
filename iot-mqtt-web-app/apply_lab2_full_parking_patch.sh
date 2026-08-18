#!/usr/bin/env bash
set -euo pipefail

# CSE3CWA / CSE5006 Week 7 - Lab 2 complete patch
# Applies the tested Lab 2 UI control + full Parking UI + live parking data
# directly to the original Week 7 iot-mqtt-web-app project in one command.

ROOT="$(cd "$(dirname "$0")" && pwd)"
SERVER="$ROOT/iot_mqtt_dashboard/server/src/server.js"
CLIENT="$ROOT/iot_mqtt_dashboard/client/src/main.jsx"
CSS="$ROOT/iot_mqtt_dashboard/client/src/styles.css"

for f in "$SERVER" "$CLIENT" "$CSS"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: Expected Week 7 file not found: $f"
    echo "Place this script in the iot-mqtt-web-app folder and run it there."
    exit 1
  fi
done

# This complete patch is intended for the original Week 7 source.
if grep -q 'LAB2_FULL_PARKING_DATA_PATCH' "$SERVER" && grep -q 'LAB2_FULL_PARKING_DATA_PATCH' "$CLIENT"; then
  echo "Lab 2 complete patch is already applied. Nothing to do."
  exit 0
fi
if grep -q 'LAB2_UI_MODE_PATCH\|LAB2_ULTIMATE_PARKING_PATCH\|LAB2_FULL_PARKING_DATA_PATCH' "$SERVER" "$CLIENT" 2>/dev/null; then
  echo "ERROR: This one-step patch expects the original Week 7 source code."
  echo "Your files already contain an earlier Lab 2 patch marker."
  echo "Restore the original Week 7 files/repository, then run this script once."
  exit 1
fi

BACKUP_DIR="$ROOT/.lab2-original-backup"
mkdir -p "$BACKUP_DIR"
cp "$SERVER" "$BACKUP_DIR/server.js"
cp "$CLIENT" "$BACKUP_DIR/main.jsx"
cp "$CSS" "$BACKUP_DIR/styles.css"

TMPDIR_LAB2="$(mktemp -d)"
cleanup() { rm -rf "$TMPDIR_LAB2"; }
trap cleanup EXIT

rollback() {
  echo "ERROR: Lab 2 patch failed. Restoring original files..."
  cp "$BACKUP_DIR/server.js" "$SERVER"
  cp "$BACKUP_DIR/main.jsx" "$CLIENT"
  cp "$BACKUP_DIR/styles.css" "$CSS"
  exit 1
}
trap rollback ERR

cat > "$TMPDIR_LAB2/step1.sh" <<'STEP1'
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SERVER="$ROOT/iot_mqtt_dashboard/server/src/server.js"
CLIENT="$ROOT/iot_mqtt_dashboard/client/src/main.jsx"
CSS="$ROOT/iot_mqtt_dashboard/client/src/styles.css"

for f in "$SERVER" "$CLIENT" "$CSS"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: Expected Week 7 file not found: $f"
    echo "Place this script in the iot-mqtt-web-app folder and run it there."
    exit 1
  fi
done

if grep -q 'LAB2_UI_MODE_PATCH' "$SERVER" && grep -q 'LAB2_UI_MODE_PATCH' "$CLIENT"; then
  echo "Lab 2 patch is already applied. Nothing to do."
  exit 0
fi

cp -n "$SERVER" "$SERVER.lab1-backup"
cp -n "$CLIENT" "$CLIENT.lab1-backup"
cp -n "$CSS" "$CSS.lab1-backup"

python3 - "$SERVER" "$CLIENT" "$CSS" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
client = Path(sys.argv[2])
css = Path(sys.argv[3])

s = server.read_text()
c = client.read_text()
x = css.read_text()

def replace_once(text, old, new, label):
    if old not in text:
        raise SystemExit(f"ERROR: Could not find expected {label}. The source file may not match the Week 7 Lab 1 version.")
    return text.replace(old, new, 1)

# ---------------- Backend ----------------
s = replace_once(s,
'''let mongoClient;\nlet readings;\nlet mqttClient;\n''',
'''let mongoClient;\nlet readings;\nlet mqttClient;\n\n// LAB2_UI_MODE_PATCH: a small MQTT control channel for the live UI.\nconst uiControlTopic = "latrobe/ui/mode";\nconst supportedUiModes = new Set(["environment", "parking"]);\nlet uiMode = "environment";\nconst sseClients = new Set();\n\nfunction sendSseEvent(res, eventName, payload) {\n  res.write(`event: ${eventName}\\n`);\n  res.write(`data: ${JSON.stringify(payload)}\\n\\n`);\n}\n\nfunction broadcastUiMode() {\n  const payload = { mode: uiMode, sentAt: new Date().toISOString() };\n  for (const res of sseClients) {\n    sendSseEvent(res, "ui-mode", payload);\n  }\n}\n''', 'backend globals')

s = replace_once(s,
'''  res.flushHeaders?.();\n\n  async function sendSnapshot() {''',
'''  res.flushHeaders?.();\n\n  // LAB2_UI_MODE_PATCH: remember this browser so MQTT control messages can\n  // change the UI immediately instead of waiting for the 5-second snapshot.\n  sseClients.add(res);\n  sendSseEvent(res, "ui-mode", { mode: uiMode, sentAt: new Date().toISOString() });\n\n  async function sendSnapshot() {''', 'SSE connection setup')

s = replace_once(s,
'''  req.on("close", () => {\n    clearInterval(interval);\n  });''',
'''  req.on("close", () => {\n    clearInterval(interval);\n    sseClients.delete(res);\n  });''', 'SSE close handler')

s = replace_once(s,
'''    mqttClient.subscribe(config.mqttSubscribeTopic, { qos: 1 }, (error) => {\n      if (error) {\n        runtime.lastError = error.message;\n        console.error("[MQTT SUBSCRIBE ERROR]", error.message);\n        return;\n      }\n      console.log(`[MQTT] Subscribed to ${config.mqttSubscribeTopic}`);\n    });''',
'''    mqttClient.subscribe([config.mqttSubscribeTopic, uiControlTopic], { qos: 1 }, (error) => {\n      if (error) {\n        runtime.lastError = error.message;\n        console.error("[MQTT SUBSCRIBE ERROR]", error.message);\n        return;\n      }\n      console.log(`[MQTT] Subscribed to ${config.mqttSubscribeTopic}`);\n      console.log(`[MQTT] Subscribed to ${uiControlTopic} (Lab 2 UI control)`);\n    });''', 'MQTT subscription')

s = replace_once(s,
'''  mqttClient.on("message", async (topic, message) => {\n    try {\n      await storeReading(topic, message);\n    } catch (error) {\n      runtime.lastError = error.message;\n      console.error("[MQTT MESSAGE ERROR]", error.message);\n    }\n  });''',
'''  mqttClient.on("message", async (topic, message) => {\n    try {\n      // LAB2_UI_MODE_PATCH: UI control messages are commands, not sensor\n      // readings, so they are not inserted into MongoDB.\n      if (topic === uiControlTopic) {\n        const requestedMode = message.toString("utf8").trim().toLowerCase();\n        if (!supportedUiModes.has(requestedMode)) {\n          console.log(`[UI] Ignored unsupported mode: ${requestedMode}`);\n          return;\n        }\n        uiMode = requestedMode;\n        console.log(`[UI] Mode changed to ${uiMode}`);\n        broadcastUiMode();\n        return;\n      }\n\n      await storeReading(topic, message);\n    } catch (error) {\n      runtime.lastError = error.message;\n      console.error("[MQTT MESSAGE ERROR]", error.message);\n    }\n  });''', 'MQTT message handler')

# ---------------- Frontend ----------------
c = replace_once(c,
'''function ReadingCards({ readings }) {''',
'''// LAB2_UI_MODE_PATCH: this is deliberately a lightweight alternate view.\n// The existing metrics, chart and MongoDB table remain below it.\nfunction ParkingView() {\n  return (\n    <section className="parking-view">\n      <div>\n        <p className="eyebrow">MQTT-controlled view</p>\n        <h2>Smart Parking</h2>\n        <p>Parking mode is active. The existing IoT pipeline and dashboard tools are still running below.</p>\n      </div>\n      <div className="parking-signal">P</div>\n    </section>\n  );\n}\n\nfunction ReadingCards({ readings }) {''', 'ParkingView insertion')

c = replace_once(c,
'''  const [error, setError] = useState("");\n\n  // Filter controls.''',
'''  const [error, setError] = useState("");\n  // LAB2_UI_MODE_PATCH: changed immediately by the backend's SSE ui-mode event.\n  const [uiMode, setUiMode] = useState("environment");\n\n  // Filter controls.''', 'uiMode state')

c = replace_once(c,
'''    source.addEventListener("snapshot", (event) => {\n      const payload = JSON.parse(event.data);\n      setReadings(payload.readings || []);\n      setSeries(payload.series || []);\n      setSensorTypes(payload.sensorTypes || []);\n      setRuntime(payload.runtime || null);\n      setLastSnapshot(payload.sentAt);\n      setConnectionState("connected");\n    });\n\n    source.addEventListener("stream-error", (event) => {''',
'''    source.addEventListener("snapshot", (event) => {\n      const payload = JSON.parse(event.data);\n      setReadings(payload.readings || []);\n      setSeries(payload.series || []);\n      setSensorTypes(payload.sensorTypes || []);\n      setRuntime(payload.runtime || null);\n      setLastSnapshot(payload.sentAt);\n      setConnectionState("connected");\n    });\n\n    // LAB2_UI_MODE_PATCH: MQTT -> backend -> immediate SSE event -> React.\n    source.addEventListener("ui-mode", (event) => {\n      const payload = JSON.parse(event.data);\n      if (payload.mode === "environment" || payload.mode === "parking") {\n        setUiMode(payload.mode);\n      }\n    });\n\n    source.addEventListener("stream-error", (event) => {''', 'ui-mode SSE listener')

c = replace_once(c,
'''          <p className="eyebrow">Week 7 · MQTT + MongoDB + React</p>\n          <h1>IoT Telemetry Dashboard</h1>\n          <p className="hero-copy">\n            The backend subscribes to MQTT topics, stores each sensor message in MongoDB, and streams a fresh snapshot to this React interface every few seconds. The chart and table below update on their own.\n          </p>''',
'''          <p className="eyebrow">Week 7 · MQTT + MongoDB + React</p>\n          <h1>{uiMode === "parking" ? "Smart Parking Dashboard" : "IoT Telemetry Dashboard"}</h1>\n          <p className="hero-copy">\n            {uiMode === "parking"\n              ? "Parking mode was activated by an MQTT control message. The same backend, MongoDB connection, SSE stream, chart and table remain available."\n              : "The backend subscribes to MQTT topics, stores each sensor message in MongoDB, and streams a fresh snapshot to this React interface every few seconds. The chart and table below update on their own."}\n          </p>''', 'hero mode')

c = replace_once(c,
'''      <ReadingCards readings={readings} />\n\n      <section className="panel">''',
'''      {uiMode === "parking" ? <ParkingView /> : <ReadingCards readings={readings} />}\n\n      <section className="panel">''', 'domain view switch')

# ---------------- CSS ----------------
if 'LAB2_UI_MODE_PATCH' not in x:
    x += '''\n\n/* LAB2_UI_MODE_PATCH -------------------------------------------------- */\n.parking-view {\n  display: flex;\n  align-items: center;\n  justify-content: space-between;\n  gap: 1.5rem;\n  background: #ffffff;\n  border: 1px solid var(--line);\n  border-radius: var(--radius);\n  padding: 1.4rem 1.6rem;\n  box-shadow: var(--shadow);\n}\n.parking-view h2 { margin: 0.2rem 0 0.35rem; color: var(--brand); font-size: 1.6rem; }\n.parking-view p { margin: 0; color: var(--muted); }\n.parking-signal {\n  width: 68px;\n  height: 68px;\n  border-radius: 16px;\n  display: grid;\n  place-items: center;\n  flex: 0 0 auto;\n  background: var(--brand);\n  color: #fff;\n  font-size: 2rem;\n  font-weight: 900;\n}\n'''

server.write_text(s)
client.write_text(c)
css.write_text(x)
PY

echo "Lab 2 patch applied successfully."
echo "Backups created beside the original files with the suffix .lab1-backup"
echo "Restart iot_mqtt_dashboard/run_ubuntu.sh before testing the MQTT UI command."
STEP1
cat > "$TMPDIR_LAB2/step2.sh" <<'STEP2'
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CLIENT="$ROOT/iot_mqtt_dashboard/client/src/main.jsx"
CSS="$ROOT/iot_mqtt_dashboard/client/src/styles.css"
SERVER="$ROOT/iot_mqtt_dashboard/server/src/server.js"

for f in "$SERVER" "$CLIENT" "$CSS"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: Expected Week 7 file not found: $f"
    echo "Place this script in the iot-mqtt-web-app folder and run it there."
    exit 1
  fi
done

if ! grep -q 'LAB2_UI_MODE_PATCH' "$SERVER" || ! grep -q 'LAB2_UI_MODE_PATCH' "$CLIENT"; then
  echo "ERROR: The Lab 2 MQTT UI-mode patch is not installed yet."
  echo "Apply apply_lab2_patch.sh first, then run this upgrade patch."
  exit 1
fi

if grep -q 'LAB2_ULTIMATE_PARKING_PATCH' "$CLIENT"; then
  echo "Lab 2 ultimate parking patch is already applied. Nothing to do."
  exit 0
fi

cp -n "$CLIENT" "$CLIENT.lab2-mode-backup"
cp -n "$CSS" "$CSS.lab2-mode-backup"

python3 - "$CLIENT" "$CSS" <<'PY'
from pathlib import Path
import sys

client = Path(sys.argv[1])
css = Path(sys.argv[2])
c = client.read_text()
x = css.read_text()

old = '''// LAB2_UI_MODE_PATCH: this is deliberately a lightweight alternate view.\n// The existing metrics, chart and MongoDB table remain below it.\nfunction ParkingView() {\n  return (\n    <section className="parking-view">\n      <div>\n        <p className="eyebrow">MQTT-controlled view</p>\n        <h2>Smart Parking</h2>\n        <p>Parking mode is active. The existing IoT pipeline and dashboard tools are still running below.</p>\n      </div>\n      <div className="parking-signal">P</div>\n    </section>\n  );\n}\n'''

new = '''// LAB2_ULTIMATE_PARKING_PATCH: a complete alternate application view.\n// It deliberately does not display environmental temperature/humidity/pressure\n// data as parking data. The shared backend/MQTT/MongoDB/SSE runtime remains live.\nfunction ParkingDashboard({ runtime, connectionState }) {\n  const mqttConnected = runtime?.mqttConnected === true;\n  const mongodbConnected = runtime?.mongodbConnected === true;\n\n  return (\n    <main className="page-shell parking-shell">\n      <section className="parking-hero">\n        <div>\n          <p className="parking-kicker">Week 7 · MQTT-controlled application mode</p>\n          <h1>Smart Parking</h1>\n          <p className="parking-copy">\n            Parking mode is active. The same Mosquitto broker, Node/Express backend,\n            MongoDB connection and SSE stream are still running underneath this view.\n          </p>\n        </div>\n        <div className="parking-sign">P</div>\n      </section>\n\n      <section className="parking-status-grid">\n        <article>\n          <span>Live stream</span>\n          <strong>{connectionState === "connected" ? "ONLINE" : connectionState.toUpperCase()}</strong>\n        </article>\n        <article>\n          <span>MQTT broker</span>\n          <strong>{mqttConnected ? "CONNECTED" : "DISCONNECTED"}</strong>\n        </article>\n        <article>\n          <span>MongoDB</span>\n          <strong>{mongodbConnected ? "CONNECTED" : "DISCONNECTED"}</strong>\n        </article>\n      </section>\n\n      <section className="parking-overview">\n        <div className="parking-overview-heading">\n          <div>\n            <p className="parking-kicker">Parking overview</p>\n            <h2>Waiting for parking telemetry</h2>\n            <p>\n              The MQTT control message changed the application mode, but it did not\n              invent parking-bay measurements. No environmental sensor values are\n              presented as parking data.\n            </p>\n          </div>\n          <span className="parking-mode-badge">PARKING MODE</span>\n        </div>\n\n        <div className="parking-bay-grid" aria-label="Parking bays waiting for telemetry">\n          {[1, 2, 3, 4, 5, 6].map((number) => (\n            <article className="parking-bay waiting" key={number}>\n              <span>Bay {String(number).padStart(2, "0")}</span>\n              <strong>NO DATA</strong>\n            </article>\n          ))}\n        </div>\n      </section>\n\n      <section className="parking-command-panel">\n        <p className="parking-kicker">MQTT control channel</p>\n        <h2>This screen was selected by MQTT</h2>\n        <p>\n          Publish <code>environment</code> to <code>latrobe/ui/mode</code> to restore\n          the complete environmental telemetry dashboard immediately.\n        </p>\n      </section>\n\n      <footer className="page-footer">\n        <p>Week 7 IoT MQTT Dashboard · Copyright (c) 2026 Dr Shuo Ding · Licensed under AGPL-3.0-or-later.</p>\n      </footer>\n    </main>\n  );\n}\n'''

if old not in c:
    raise SystemExit('ERROR: Could not find the Lab 2 ParkingView from the first patch. The frontend does not match the tested Week 7 patched version.')
c = c.replace(old, new, 1)

old_return = '''  return (\n    <main className="page-shell">\n      <section className="hero">'''
new_return = '''  // LAB2_ULTIMATE_PARKING_PATCH: parking replaces the whole environmental\n  // presentation. The environmental React state remains in memory and returns\n  // unchanged when MQTT switches the mode back to environment.\n  if (uiMode === "parking") {\n    return (\n      <ParkingDashboard\n        runtime={runtime}\n        connectionState={connectionState}\n      />\n    );\n  }\n\n  return (\n    <main className="page-shell">\n      <section className="hero">'''
if old_return not in c:
    raise SystemExit('ERROR: Could not find the App return block in the tested Week 7 frontend.')
c = c.replace(old_return, new_return, 1)

c = c.replace('''          <h1>{uiMode === "parking" ? "Smart Parking Dashboard" : "IoT Telemetry Dashboard"}</h1>\n          <p className="hero-copy">\n            {uiMode === "parking"\n              ? "Parking mode was activated by an MQTT control message. The same backend, MongoDB connection, SSE stream, chart and table remain available."\n              : "The backend subscribes to MQTT topics, stores each sensor message in MongoDB, and streams a fresh snapshot to this React interface every few seconds. The chart and table below update on their own."}\n          </p>''', '''          <h1>IoT Telemetry Dashboard</h1>\n          <p className="hero-copy">\n            The backend subscribes to MQTT topics, stores each sensor message in MongoDB, and streams a fresh snapshot to this React interface every few seconds. The chart and table below update on their own.\n          </p>''', 1)

c = c.replace('''      {uiMode === "parking" ? <ParkingView /> : <ReadingCards readings={readings} />}''', '''      <ReadingCards readings={readings} />''', 1)

x += '''\n\n/* LAB2_ULTIMATE_PARKING_PATCH --------------------------------------- */\n.parking-shell { min-height: 100vh; }\n.parking-hero {\n  display: flex;\n  align-items: center;\n  justify-content: space-between;\n  gap: 2rem;\n  background: #111827;\n  color: #fff;\n  border-radius: var(--radius);\n  padding: 2rem;\n  box-shadow: var(--shadow);\n}\n.parking-hero h1 { margin: 0.2rem 0 0.55rem; font-size: clamp(2rem, 5vw, 3.2rem); }\n.parking-copy { margin: 0; max-width: 720px; color: #d1d5db; }\n.parking-kicker { margin: 0; font-size: 0.78rem; font-weight: 800; letter-spacing: 0.09em; text-transform: uppercase; color: #6b7280; }\n.parking-hero .parking-kicker { color: #fbbf24; }\n.parking-sign {\n  width: 92px;\n  height: 92px;\n  border-radius: 20px;\n  display: grid;\n  place-items: center;\n  flex: 0 0 auto;\n  background: #fbbf24;\n  color: #111827;\n  font-size: 3.4rem;\n  line-height: 1;\n  font-weight: 900;\n}\n.parking-status-grid {\n  display: grid;\n  grid-template-columns: repeat(3, minmax(0, 1fr));\n  gap: 1rem;\n}\n.parking-status-grid article {\n  background: #fff;\n  border: 1px solid var(--line);\n  border-radius: var(--radius);\n  padding: 1rem 1.2rem;\n  box-shadow: var(--shadow);\n}\n.parking-status-grid span { display: block; color: var(--muted); font-size: 0.82rem; margin-bottom: 0.25rem; }\n.parking-status-grid strong { color: #111827; font-size: 1rem; }\n.parking-overview, .parking-command-panel {\n  background: #fff;\n  border: 1px solid var(--line);\n  border-radius: var(--radius);\n  padding: 1.5rem;\n  box-shadow: var(--shadow);\n}\n.parking-overview-heading { display: flex; justify-content: space-between; align-items: flex-start; gap: 1.5rem; }\n.parking-overview h2, .parking-command-panel h2 { margin: 0.25rem 0 0.45rem; color: #111827; }\n.parking-overview-heading p:not(.parking-kicker), .parking-command-panel p:not(.parking-kicker) { margin: 0; color: var(--muted); }\n.parking-mode-badge {\n  display: inline-block;\n  white-space: nowrap;\n  padding: 0.35rem 0.7rem;\n  border-radius: 999px;\n  background: #fef3c7;\n  color: #92400e;\n  font-size: 0.76rem;\n  font-weight: 800;\n}\n.parking-bay-grid {\n  display: grid;\n  grid-template-columns: repeat(3, minmax(0, 1fr));\n  gap: 0.9rem;\n  margin-top: 1.25rem;\n}\n.parking-bay {\n  min-height: 105px;\n  border-radius: 12px;\n  border: 2px dashed #d1d5db;\n  background: #f9fafb;\n  padding: 1rem;\n  display: flex;\n  flex-direction: column;\n  justify-content: space-between;\n}\n.parking-bay span { color: #4b5563; font-weight: 700; }\n.parking-bay strong { color: #9ca3af; font-size: 1.05rem; }\n.parking-command-panel code { font-family: Consolas, "Courier New", monospace; }\n@media (max-width: 720px) {\n  .parking-hero, .parking-overview-heading { flex-direction: column; }\n  .parking-status-grid, .parking-bay-grid { grid-template-columns: 1fr; }\n}\n'''

client.write_text(c)
css.write_text(x)
PY

node --check "$SERVER"
echo "Lab 2 ultimate parking patch applied successfully."
echo "The MQTT control channel is unchanged: latrobe/ui/mode"
echo "Parking mode now replaces the entire environmental data presentation."
echo "Environmental readings remain in React state and reappear when mode returns to environment."
echo "Restart iot_mqtt_dashboard/run_ubuntu.sh before testing."
STEP2
cat > "$TMPDIR_LAB2/step3.sh" <<'STEP3'
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CLIENT="$ROOT/iot_mqtt_dashboard/client/src/main.jsx"
CSS="$ROOT/iot_mqtt_dashboard/client/src/styles.css"
SERVER="$ROOT/iot_mqtt_dashboard/server/src/server.js"

for f in "$SERVER" "$CLIENT" "$CSS"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: Expected Week 7 file not found: $f"
    echo "Place this script in the iot-mqtt-web-app folder and run it there."
    exit 1
  fi
done

if ! grep -q 'LAB2_UI_MODE_PATCH' "$SERVER" || ! grep -q 'LAB2_ULTIMATE_PARKING_PATCH' "$CLIENT"; then
  echo "ERROR: Apply apply_lab2_patch.sh and apply_lab2_ultimate_patch.sh first."
  exit 1
fi

if grep -q 'LAB2_FULL_PARKING_DATA_PATCH' "$SERVER" && grep -q 'LAB2_FULL_PARKING_DATA_PATCH' "$CLIENT"; then
  echo "Lab 2 full parking-data patch is already applied. Nothing to do."
  exit 0
fi

cp -n "$SERVER" "$SERVER.before-full-parking-backup"
cp -n "$CLIENT" "$CLIENT.before-full-parking-backup"
cp -n "$CSS" "$CSS.before-full-parking-backup"

python3 - "$SERVER" "$CLIENT" "$CSS" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1]); client = Path(sys.argv[2]); css = Path(sys.argv[3])
s = server.read_text(); c = client.read_text(); x = css.read_text()

# SERVER: latest parking reading per bay, using the existing normalized location.room.
needle = '''async function getRecentReadings(limit = 30) {
  return readings
    .find({}, { projection: readingProjection })
    .sort({ receivedAt: -1 })
    .limit(limit)
    .toArray();
}
'''
insert = needle + '''
// LAB2_FULL_PARKING_DATA_PATCH: latest occupancy reading for each bay in carpark-a.
// Parking messages use the existing five-level Week 7 topic shape:
// latrobe/carpark-a/level-1/bay-01/occupancy
async function getLatestParkingReadings() {
  return readings
    .aggregate([
      { $match: { "location.building": "carpark-a", sensorType: "occupancy" } },
      { $sort: { receivedAt: -1 } },
      { $group: { _id: "$location.room", reading: { $first: "$$ROOT" } } },
      { $replaceRoot: { newRoot: "$reading" } },
      { $sort: { "location.room": 1 } },
      { $project: readingProjection }
    ])
    .toArray();
}

async function broadcastParkingReadings() {
  const payload = {
    readings: await getLatestParkingReadings(),
    sentAt: new Date().toISOString()
  };
  for (const res of sseClients) {
    sendSseEvent(res, "parking-data", payload);
  }
}
'''
if needle not in s:
    raise SystemExit('ERROR: Could not find getRecentReadings() in server.js')
s = s.replace(needle, insert, 1)

# Add parking readings to regular snapshot for refresh/reconnect.
needle = '''        readings: await getLatestReadings(),
        sensorTypes: await getSensorTypes(),
        series: await getSeries({ sensorType: "all", minutes: 0, limit: 300 })'''
repl = '''        readings: await getLatestReadings(),
        sensorTypes: await getSensorTypes(),
        series: await getSeries({ sensorType: "all", minutes: 0, limit: 300 }),
        // LAB2_FULL_PARKING_DATA_PATCH: keep parking state available after refresh/reconnect.
        parkingReadings: await getLatestParkingReadings()'''
if needle not in s:
    raise SystemExit('ERROR: Could not find SSE snapshot payload in server.js')
s = s.replace(needle, repl, 1)

# After normal sensor storage, immediately push parking state if this was parking occupancy.
needle = '''      await storeReading(topic, message);
    } catch (error) {'''
repl = '''      await storeReading(topic, message);

      // LAB2_FULL_PARKING_DATA_PATCH: parking telemetry updates the parking UI
      // immediately instead of waiting for the next 5-second snapshot.
      const topicInfo = parseTopic(topic);
      if (topicInfo.building === "carpark-a" && topicInfo.sensorType === "occupancy") {
        await broadcastParkingReadings();
      }
    } catch (error) {'''
if needle not in s:
    raise SystemExit('ERROR: Could not find MQTT storeReading call in server.js')
s = s.replace(needle, repl, 1)

# CLIENT: ParkingDashboard takes real parking readings.
c = c.replace('function ParkingDashboard({ runtime, connectionState }) {',
              'function ParkingDashboard({ runtime, connectionState, parkingReadings }) {', 1)

needle = '''  const mqttConnected = runtime?.mqttConnected === true;
  const mongodbConnected = runtime?.mongodbConnected === true;

  return ('''
repl = '''  const mqttConnected = runtime?.mqttConnected === true;
  const mongodbConnected = runtime?.mongodbConnected === true;

  // LAB2_FULL_PARKING_DATA_PATCH: map real MQTT occupancy readings to Bay 01-06.
  const latestByBay = new Map(
    (parkingReadings || []).map((reading) => [reading.location?.room, reading])
  );
  const bays = [1, 2, 3, 4, 5, 6].map((number) => {
    const id = `bay-${String(number).padStart(2, "0")}`;
    const reading = latestByBay.get(id);
    const status = !reading ? "NO DATA" : Number(reading.value) === 1 ? "OCCUPIED" : "FREE";
    return { number, id, reading, status };
  });
  const knownBays = bays.filter((bay) => bay.reading);
  const occupiedCount = knownBays.filter((bay) => bay.status === "OCCUPIED").length;
  const freeCount = knownBays.filter((bay) => bay.status === "FREE").length;

  return ('''
if needle not in c:
    raise SystemExit('ERROR: Could not find ParkingDashboard runtime block in main.jsx')
c = c.replace(needle, repl, 1)

# Replace waiting heading with live stats.
c = c.replace('''            <h2>Waiting for parking telemetry</h2>
            <p>
              The MQTT control message changed the application mode, but it did not
              invent parking-bay measurements. No environmental sensor values are
              presented as parking data.
            </p>''', '''            <h2>{knownBays.length ? "Live parking telemetry" : "Waiting for parking telemetry"}</h2>
            <p>
              {knownBays.length
                ? `${knownBays.length} bay(s) reporting · ${freeCount} free · ${occupiedCount} occupied.`
                : "Publish occupancy readings for Bay 01-06. Bays without a reading remain NO DATA."}
            </p>''', 1)

# Replace static bays.
needle = '''        <div className="parking-bay-grid" aria-label="Parking bays waiting for telemetry">
          {[1, 2, 3, 4, 5, 6].map((number) => (
            <article className="parking-bay waiting" key={number}>
              <span>Bay {String(number).padStart(2, "0")}</span>
              <strong>NO DATA</strong>
            </article>
          ))}
        </div>'''
repl = '''        <div className="parking-bay-grid" aria-label="Live parking bay occupancy">
          {bays.map((bay) => (
            <article className={`parking-bay ${bay.status.toLowerCase().replace(" ", "-")}`} key={bay.id}>
              <span>Bay {String(bay.number).padStart(2, "0")}</span>
              <strong>{bay.status}</strong>
              <small>{bay.reading ? `Updated ${formatTime(bay.reading.receivedAt)}` : "Waiting for MQTT data"}</small>
            </article>
          ))}
        </div>'''
if needle not in c:
    raise SystemExit('ERROR: Could not find static parking bay grid in main.jsx')
c = c.replace(needle, repl, 1)

# Add parking state.
needle = '''  const [uiMode, setUiMode] = useState("environment");'''
repl = '''  const [uiMode, setUiMode] = useState("environment");
  // LAB2_FULL_PARKING_DATA_PATCH: latest occupancy reading for each parking bay.
  const [parkingReadings, setParkingReadings] = useState([]);'''
if needle not in c:
    raise SystemExit('ERROR: Could not find uiMode state in main.jsx')
c = c.replace(needle, repl, 1)

# Snapshot restores parking data.
needle = '''      setRuntime(payload.runtime || null);
      setLastSnapshot(payload.sentAt);'''
repl = '''      setRuntime(payload.runtime || null);
      setParkingReadings(payload.parkingReadings || []);
      setLastSnapshot(payload.sentAt);'''
if needle not in c:
    raise SystemExit('ERROR: Could not find snapshot state updates in main.jsx')
c = c.replace(needle, repl, 1)

# Immediate parking-data event.
needle = '''    source.addEventListener("ui-mode", (event) => {
      const payload = JSON.parse(event.data);
      if (payload.mode === "environment" || payload.mode === "parking") {
        setUiMode(payload.mode);
      }
    });
'''
repl = needle + '''
    // LAB2_FULL_PARKING_DATA_PATCH: real parking MQTT readings arrive here
    // immediately after the backend stores them in MongoDB.
    source.addEventListener("parking-data", (event) => {
      const payload = JSON.parse(event.data);
      setParkingReadings(payload.readings || []);
    });
'''
if needle not in c:
    raise SystemExit('ERROR: Could not find ui-mode SSE listener in main.jsx')
c = c.replace(needle, repl, 1)

# Pass readings into parking dashboard.
needle = '''      <ParkingDashboard
        runtime={runtime}
        connectionState={connectionState}
      />'''
repl = '''      <ParkingDashboard
        runtime={runtime}
        connectionState={connectionState}
        parkingReadings={parkingReadings}
      />'''
if needle not in c:
    raise SystemExit('ERROR: Could not find ParkingDashboard call in main.jsx')
c = c.replace(needle, repl, 1)

# CSS for real states.
x += '''

/* LAB2_FULL_PARKING_DATA_PATCH --------------------------------------- */
.parking-bay small { color: #6b7280; font-size: 0.74rem; margin-top: 0.65rem; }
.parking-bay.free { border-style: solid; border-color: #86efac; background: #f0fdf4; }
.parking-bay.free strong { color: #15803d; }
.parking-bay.occupied { border-style: solid; border-color: #fca5a5; background: #fef2f2; }
.parking-bay.occupied strong { color: #b91c1c; }
.parking-bay.no-data { border-style: dashed; border-color: #d1d5db; background: #f9fafb; }
.parking-bay.no-data strong { color: #9ca3af; }
'''

server.write_text(s); client.write_text(c); css.write_text(x)
PY

node --check "$SERVER"
echo "Lab 2 full parking-data patch applied successfully."
echo "Parking MQTT topic format: latrobe/carpark-a/level-1/bay-01/occupancy"
echo "value 1 = OCCUPIED, value 0 = FREE."
echo "Restart iot_mqtt_dashboard/run_ubuntu.sh before testing."
STEP3
chmod +x "$TMPDIR_LAB2/step1.sh" "$TMPDIR_LAB2/step2.sh" "$TMPDIR_LAB2/step3.sh"

# The embedded tested transformations expect to live in the project root.
cp "$TMPDIR_LAB2/step1.sh" "$ROOT/.lab2_step1_tmp.sh"
cp "$TMPDIR_LAB2/step2.sh" "$ROOT/.lab2_step2_tmp.sh"
cp "$TMPDIR_LAB2/step3.sh" "$ROOT/.lab2_step3_tmp.sh"
chmod +x "$ROOT/.lab2_step1_tmp.sh" "$ROOT/.lab2_step2_tmp.sh" "$ROOT/.lab2_step3_tmp.sh"

"$ROOT/.lab2_step1_tmp.sh" >/dev/null
"$ROOT/.lab2_step2_tmp.sh" >/dev/null
"$ROOT/.lab2_step3_tmp.sh" >/dev/null
rm -f "$ROOT/.lab2_step1_tmp.sh" "$ROOT/.lab2_step2_tmp.sh" "$ROOT/.lab2_step3_tmp.sh"

node --check "$SERVER"

trap - ERR

echo "Lab 2 complete patch applied successfully."
echo "Added MQTT UI control topic: latrobe/ui/mode"
echo "Added full Smart Parking view."
echo "Added live parking occupancy data for Bay 01-06."
echo "Parking topic example: latrobe/carpark-a/level-1/bay-01/occupancy"
echo "Parking value 1 = OCCUPIED; value 0 = FREE."
echo "Original files are backed up in: $BACKUP_DIR"
echo "Restart iot_mqtt_dashboard/run_ubuntu.sh before testing."
