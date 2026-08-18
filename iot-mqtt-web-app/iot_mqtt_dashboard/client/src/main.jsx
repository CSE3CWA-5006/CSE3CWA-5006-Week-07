/* Smart City IoT Operations Console - React frontend. Copyright (c) 2026 Dr Shuo Ding. AGPL-3.0-or-later. */
import React, { useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import "./styles.css";

const apiBase = import.meta.env.VITE_API_BASE || "http://localhost:4100";
const SENSOR_META = {
  temperature: { label: "Temperature", colour: "#e05d3f", unit: "°C" },
  humidity: { label: "Humidity", colour: "#13a17b", unit: "%" },
  pressure: { label: "Pressure", colour: "#3f6fd9", unit: "hPa" }
};
const metaFor = (type) => SENSOR_META[type] || { label: type, colour: "#7c6ee6", unit: "" };
const roomKey = (location = {}) => `${location.building || "unknown"}/${location.level || "unknown"}/${location.room || "unknown"}`;
const normaliseBayId = (value = "") => {
  const text = String(value).trim().toLowerCase();
  const match = text.match(/^bay-?0*(\d+)$/);
  return match ? `bay-${String(Number(match[1])).padStart(2, "0")}` : text;
};
const titleCase = (value = "") => value.split("-").map((x) => x ? x[0].toUpperCase() + x.slice(1) : x).join(" ");
function formatTime(value) { if (!value) return "Not yet"; return new Intl.DateTimeFormat("en-AU", { hour: "2-digit", minute: "2-digit", second: "2-digit" }).format(new Date(value)); }
function formatDateTime(value) { if (!value) return "Not yet"; return new Intl.DateTimeFormat("en-AU", { dateStyle: "medium", timeStyle: "medium" }).format(new Date(value)); }

function LineChart({ points, colour, unit }) {
  const width = 760, height = 250, padding = { top: 22, right: 22, bottom: 30, left: 50 };
  if (!points?.length) return <div className="chart-empty">Waiting for readings…</div>;
  const values = points.map((p) => p.value), times = points.map((p) => new Date(p.receivedAt).getTime());
  const minValue = Math.min(...values), maxValue = Math.max(...values), valuePad = (maxValue - minValue || 1) * 0.15;
  const yMin = minValue - valuePad, yMax = maxValue + valuePad, minTime = Math.min(...times), maxTime = Math.max(...times), timeSpan = maxTime - minTime || 1;
  const plotWidth = width - padding.left - padding.right, plotHeight = height - padding.top - padding.bottom;
  const xFor = (t) => padding.left + ((t - minTime) / timeSpan) * plotWidth;
  const yFor = (v) => padding.top + (1 - (v - yMin) / (yMax - yMin)) * plotHeight;
  const linePath = points.map((p, i) => `${i ? "L" : "M"} ${xFor(times[i]).toFixed(1)} ${yFor(p.value).toFixed(1)}`).join(" ");
  const areaPath = `${linePath} L ${xFor(maxTime).toFixed(1)} ${(padding.top + plotHeight).toFixed(1)} L ${xFor(minTime).toFixed(1)} ${(padding.top + plotHeight).toFixed(1)} Z`;
  const grid = Array.from({ length: 5 }, (_, i) => { const value = yMin + ((yMax - yMin) * i) / 4; return { value, y: yFor(value) }; });
  const last = points[points.length - 1];
  return <svg className="chart-svg" viewBox={`0 0 ${width} ${height}`} role="img" aria-label={`${unit} over time`}>
    {grid.map((g, i) => <g key={i}><line x1={padding.left} y1={g.y} x2={width-padding.right} y2={g.y} stroke="#e8edf5"/><text x={padding.left-9} y={g.y+4} textAnchor="end" fontSize="11" fill="#8792a7">{g.value.toFixed(1)}</text></g>)}
    <path d={areaPath} fill={colour} opacity="0.09"/><path d={linePath} fill="none" stroke={colour} strokeWidth="2.7" strokeLinejoin="round" strokeLinecap="round"/>
    <circle cx={xFor(times.at(-1))} cy={yFor(last.value)} r="4.5" fill={colour}/>
    <text x={xFor(times.at(-1))} y={yFor(last.value)-11} textAnchor="middle" fontSize="12" fontWeight="700" fill={colour}>{last.value} {unit}</text>
    <text x={padding.left} y={height-8} fontSize="11" fill="#8792a7">{formatTime(points[0].receivedAt)}</text>
    <text x={width-padding.right} y={height-8} textAnchor="end" fontSize="11" fill="#8792a7">{formatTime(last.receivedAt)}</text>
  </svg>;
}

function StatusStrip({ runtime, connectionState }) {
  const items = [
    ["Live stream", connectionState === "connected" ? "Online" : connectionState],
    ["MQTT broker", runtime?.mqttConnected ? "Connected" : "Offline"],
    ["Data store", runtime?.mongodbConnected ? "Connected" : "Offline"]
  ];
  return <div className="status-strip">{items.map(([label, value]) => <div key={label}><span className={`status-dot ${String(value).toLowerCase()}`}/><p>{label}</p><strong>{value}</strong></div>)}</div>;
}

function EnvironmentView({ readings, rooms, sensorTypes, selectedRoom, setSelectedRoom, selectedSensor, setSelectedSensor, windowMinutes, setWindowMinutes, lastSnapshot, error }) {
  const room = rooms.find((r) => r.key === selectedRoom) || rooms[0];
  const effectiveRoom = room?.key || selectedRoom;
  const roomReadings = readings.filter((r) => r.sensorType !== "occupancy" && roomKey(r.location) === effectiveRoom);
  const [chartPoints, setChartPoints] = useState([]);
  useEffect(() => {
    if (!room) { setChartPoints([]); return; }
    const params = new URLSearchParams({ sensorType: selectedSensor, minutes: String(windowMinutes), limit: "1000", building: room.building, level: room.level, room: room.room });
    fetch(`${apiBase}/api/readings/series?${params}`).then((r) => r.json()).then((p) => setChartPoints(p.data || [])).catch(() => setChartPoints([]));
  }, [room?.key, selectedSensor, windowMinutes, lastSnapshot]);
  const meta = metaFor(selectedSensor);
  const availableSensors = sensorTypes.length ? sensorTypes : Object.keys(SENSOR_META);
  return <>
    <section className="view-heading"><div><p className="eyebrow">Environmental intelligence</p><h2>{room ? `${titleCase(room.room)} · ${titleCase(room.building)}` : "Environmental monitoring"}</h2><p>Live conditions and historical telemetry for the selected room.</p></div>
      <label className="room-slicer"><span>Room</span><select value={effectiveRoom || ""} onChange={(e)=>setSelectedRoom(e.target.value)}>{rooms.map((r)=><option key={r.key} value={r.key}>{titleCase(r.room)} · {titleCase(r.level)} · {titleCase(r.building)}</option>)}</select></label>
    </section>
    {!rooms.length ? <div className="empty-state"><h2>No room telemetry yet</h2><p>Publish a five-level MQTT reading such as <code>latrobe/building-a/level-2/room-204/temperature</code>.</p></div> :
    <div className="card-grid">{roomReadings.map((reading)=>{const m=metaFor(reading.sensorType);return <article className="reading-card" key={`${effectiveRoom}-${reading.sensorType}`} style={{"--sensor-colour":m.colour}}><div className="card-accent"/><p className="reading-card-label">{m.label}</p><p className="reading-card-value">{reading.value}<span> {reading.unit}</span></p><p className="reading-card-device">{reading.deviceId}</p><p className="reading-card-time">Updated {formatTime(reading.receivedAt)}</p></article>})}</div>}
    <section className="panel"><div className="panel-header"><div><p className="eyebrow">Telemetry history</p><h2>{meta.label} over time</h2><p>{room ? titleCase(room.room) : "Selected room"} · last {windowMinutes} minute(s) · {chartPoints.length} point(s)</p></div><div className="controls"><label>Sensor<select value={selectedSensor} onChange={(e)=>setSelectedSensor(e.target.value)}>{availableSensors.map((t)=><option key={t} value={t}>{metaFor(t).label}</option>)}</select></label><label>Time window<select value={windowMinutes} onChange={(e)=>setWindowMinutes(Number(e.target.value))}><option value={1}>Last 1 minute</option><option value={5}>Last 5 minutes</option><option value={15}>Last 15 minutes</option><option value={60}>Last 60 minutes</option></select></label></div></div>{error?<p className="notice">{error}</p>:null}<LineChart points={chartPoints} colour={meta.colour} unit={meta.unit}/></section>
    <section className="panel"><div className="panel-header"><div><p className="eyebrow">Latest room snapshot</p><h2>Current readings</h2><p>Last interface update: {formatDateTime(lastSnapshot)}</p></div></div><ReadingTable readings={roomReadings}/></section>
  </>;
}

function ReadingTable({ readings }) {
  if (!readings.length) return <div className="table-empty">No readings for this room yet.</div>;
  return <div className="table-wrap"><table><thead><tr><th>Sensor</th><th>Value</th><th>Device</th><th>Topic</th><th>Stored</th></tr></thead><tbody>{readings.map((r)=><tr key={`${r.topic}-${r.sensorType}`}><td><span className="pill" style={{background:metaFor(r.sensorType).colour}}>{r.sensorType}</span></td><td className="value">{r.value} <span>{r.unit}</span></td><td>{r.deviceId}</td><td className="topic">{r.topic}</td><td>{formatTime(r.receivedAt)}</td></tr>)}</tbody></table></div>;
}

function ParkingView({ parkingReadings }) {
  const byBay = new Map();
  for (const reading of parkingReadings) {
    const bay = normaliseBayId(reading.location?.room);
    if (!bay) continue;
    const current = byBay.get(bay);
    if (!current || new Date(reading.receivedAt) > new Date(current.receivedAt)) byBay.set(bay, reading);
  }
  const discovered = [...byBay.keys()];
  const baseBays = Array.from({ length: 6 }, (_, i) => `bay-${String(i + 1).padStart(2, "0")}`);
  const bays = [...new Set([...baseBays, ...discovered])].sort((a,b)=>a.localeCompare(b, undefined, { numeric: true }));
  const occupied = bays.filter((bay)=>Number(byBay.get(bay)?.value)===1).length;
  const free = bays.length - occupied;
  const summary = [
    { label: "Total Bays", value: bays.length, colour: "#7158d8" },
    { label: "Free", value: free, colour: "#18a77b" },
    { label: "Occupied", value: occupied, colour: "#dc5a52" }
  ];
  return <>
    <section className="view-heading parking-heading"><div><p className="eyebrow">Mobility operations</p><h2>Smart Parking</h2><p>Live occupancy state from MQTT-connected parking bays.</p></div></section>
    <section className="card-grid parking-metric-grid">{summary.map((item)=><article className="reading-card parking-metric-card" key={item.label} style={{"--sensor-colour":item.colour}}><div className="card-accent"/><p className="reading-card-label">{item.label}</p><p className="reading-card-value">{item.value}</p><p className="reading-card-device">Parking occupancy</p><p className="reading-card-time">Live operational summary</p></article>)}</section>
    <section className="parking-grid">{bays.map((bay)=>{const r=byBay.get(bay); const state=Number(r?.value)===1?"occupied":"free";return <article className={`parking-bay ${state}`} key={bay}><div className="bay-icon">P</div><p>{titleCase(bay)}</p><strong>{state.toUpperCase()}</strong><span>{r?`Updated ${formatTime(r.receivedAt)}`:"Default state"}</span></article>})}</section>
    <section className="panel parking-note"><p className="eyebrow">Live data contract</p><h2>Parking occupancy telemetry</h2><p><code>latrobe/carpark-a/level-1/bay-01/occupancy</code> · value <strong>0</strong> = FREE · value <strong>1</strong> = OCCUPIED</p></section>
  </>;
}

function App() {
  const [readings,setReadings]=useState([]), [rooms,setRooms]=useState([]), [sensorTypes,setSensorTypes]=useState([]), [parkingReadings,setParkingReadings]=useState([]), [runtime,setRuntime]=useState(null);
  const [uiMode,setUiMode]=useState("environment"), [selectedRoom,setSelectedRoom]=useState(""), [selectedSensor,setSelectedSensor]=useState("temperature"), [windowMinutes,setWindowMinutes]=useState(5);
  const [lastSnapshot,setLastSnapshot]=useState(null), [connectionState,setConnectionState]=useState("connecting"), [error,setError]=useState("");
  useEffect(()=>{const source=new EventSource(`${apiBase}/api/stream`);source.addEventListener("open",()=>{setConnectionState("connected");setError("");});source.addEventListener("snapshot",(event)=>{const p=JSON.parse(event.data);setReadings(p.readings||[]);setRooms(p.rooms||[]);setSensorTypes(p.sensorTypes||[]);setParkingReadings(p.parkingReadings||[]);setRuntime(p.runtime||null);setUiMode(p.uiMode||"environment");setLastSnapshot(p.sentAt);setConnectionState("connected");});source.addEventListener("ui-mode",(event)=>setUiMode(JSON.parse(event.data).mode||"environment"));source.addEventListener("parking-data",(event)=>{const reading=JSON.parse(event.data).reading;if(!reading)return;setParkingReadings((current)=>{const next=current.filter((r)=>roomKey(r.location)!==roomKey(reading.location));return [...next,reading].sort((a,b)=>String(a.location?.room).localeCompare(String(b.location?.room)));});});source.addEventListener("stream-error",(event)=>setError(JSON.parse(event.data).message||"Unable to refresh live data."));source.addEventListener("error",()=>{setConnectionState("reconnecting");setError("Reconnecting to the live data service…");});return()=>source.close();},[]);
  useEffect(()=>{if(!rooms.length)return;if(!rooms.some((r)=>r.key===selectedRoom))setSelectedRoom(rooms[0].key);},[rooms,selectedRoom]);
  const metrics=useMemo(()=>({rooms:rooms.length,received:runtime?.receivedMessages||0,stored:runtime?.storedMessages||0}),[rooms,runtime]);
  return <main className="page-shell">
    <section className="hero"><div><p className="eyebrow">Connected operations platform</p><h1>Smart City IoT Operations Console</h1><p className="hero-copy">Real-time telemetry, persistent history and adaptive operational views across connected spaces.</p></div><div className={`mode-badge ${uiMode}`}><span>{uiMode==="parking"?"Parking":"Environment"}</span><small>Active workspace</small></div></section>
    <StatusStrip runtime={runtime} connectionState={connectionState}/>
    {uiMode==="environment"?<section className="metrics"><article><strong>{metrics.rooms}</strong><span>Rooms discovered</span></article><article><strong>{metrics.received}</strong><span>Telemetry received</span></article><article><strong>{metrics.stored}</strong><span>Records persisted</span></article></section>:null}
    {uiMode==="parking"?<ParkingView parkingReadings={parkingReadings}/>:<EnvironmentView readings={readings} rooms={rooms} sensorTypes={sensorTypes} selectedRoom={selectedRoom} setSelectedRoom={setSelectedRoom} selectedSensor={selectedSensor} setSelectedSensor={setSelectedSensor} windowMinutes={windowMinutes} setWindowMinutes={setWindowMinutes} lastSnapshot={lastSnapshot} error={error}/>} 
    <footer className="page-footer">© 2026 Dr Shuo Ding</footer>
  </main>;
}
createRoot(document.getElementById("root")).render(<App/>);
