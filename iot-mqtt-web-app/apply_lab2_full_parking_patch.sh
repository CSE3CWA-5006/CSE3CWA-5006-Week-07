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
