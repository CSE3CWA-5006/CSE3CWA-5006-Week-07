/*
 * Week 7 IoT MQTT Dashboard - main.jsx (React frontend)
 * Copyright (c) 2026 Dr Shuo Ding <shuoding@outlook.com>
 * Licensed under the GNU Affero General Public License v3.0 or later
 * (AGPL-3.0-or-later). Any copy, modification, or distribution must retain
 * this copyright notice and remain under the AGPL. See the LICENSE file.
 *
 * Purpose: connect to the backend Server-Sent Events stream, then show the
 * live sensor state, a real-time line chart per sensor type, and simple
 * controls to filter by sensor type and by time window. The chart is drawn
 * with plain SVG, so the dashboard has no extra charting dependency.
 */

import React, { useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import "./styles.css";

const apiBase = import.meta.env.VITE_API_BASE || "http://localhost:4100";

// Colour and unit per sensor type, used by the chart and the cards.
const SENSOR_META = {
  temperature: { label: "Temperature", colour: "#e4572e", unit: "°C" },
  humidity: { label: "Humidity", colour: "#0a8754", unit: "%" },
  pressure: { label: "Pressure", colour: "#3066be", unit: "hPa" }
};

function metaFor(sensorType) {
  return SENSOR_META[sensorType] || { label: sensorType, colour: "#6b7280", unit: "" };
}

function formatTime(value) {
  if (!value) return "Not yet";
  return new Intl.DateTimeFormat("en-AU", {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit"
  }).format(new Date(value));
}

function formatDateTime(value) {
  if (!value) return "Not yet";
  return new Intl.DateTimeFormat("en-AU", {
    dateStyle: "medium",
    timeStyle: "medium"
  }).format(new Date(value));
}

// ---------------------------------------------------------------------------
// LineChart: a small, self-contained SVG line chart.
//
// It takes a list of readings (already filtered) for ONE sensor type and
// draws a smooth line of value over time. No external chart library is used,
// so there is nothing extra to install and nothing that can break the build.
// ---------------------------------------------------------------------------
function LineChart({ points, colour, unit }) {
  const width = 720;
  const height = 240;
  const padding = { top: 20, right: 20, bottom: 28, left: 48 };

  if (!points || points.length === 0) {
    return <div className="chart-empty">Waiting for readings…</div>;
  }

  const values = points.map((p) => p.value);
  const times = points.map((p) => new Date(p.receivedAt).getTime());

  const minValue = Math.min(...values);
  const maxValue = Math.max(...values);
  // Pad the value axis a little so the line is not glued to the edges.
  const valuePad = (maxValue - minValue || 1) * 0.15;
  const yMin = minValue - valuePad;
  const yMax = maxValue + valuePad;

  const minTime = Math.min(...times);
  const maxTime = Math.max(...times);
  const timeSpan = maxTime - minTime || 1;

  const plotWidth = width - padding.left - padding.right;
  const plotHeight = height - padding.top - padding.bottom;

  function xFor(time) {
    return padding.left + ((time - minTime) / timeSpan) * plotWidth;
  }
  function yFor(value) {
    return padding.top + (1 - (value - yMin) / (yMax - yMin)) * plotHeight;
  }

  const linePath = points
    .map((p, index) => {
      const command = index === 0 ? "M" : "L";
      return `${command} ${xFor(times[index]).toFixed(1)} ${yFor(p.value).toFixed(1)}`;
    })
    .join(" ");

  // Area under the line, for a soft fill.
  const areaPath =
    `${linePath} L ${xFor(maxTime).toFixed(1)} ${(padding.top + plotHeight).toFixed(1)}` +
    ` L ${xFor(minTime).toFixed(1)} ${(padding.top + plotHeight).toFixed(1)} Z`;

  // Horizontal grid lines with value labels.
  const ticks = 4;
  const gridLines = Array.from({ length: ticks + 1 }, (_, i) => {
    const value = yMin + ((yMax - yMin) * i) / ticks;
    const y = yFor(value);
    return { value, y };
  });

  const lastPoint = points[points.length - 1];

  return (
    <svg className="chart-svg" viewBox={`0 0 ${width} ${height}`} role="img"
      aria-label={`Line chart of ${unit} over time`}>
      {gridLines.map((line, index) => (
        <g key={index}>
          <line x1={padding.left} y1={line.y} x2={width - padding.right} y2={line.y}
            stroke="#e2e8f0" strokeWidth="1" />
          <text x={padding.left - 8} y={line.y + 4} textAnchor="end"
            fontSize="11" fill="#94a3b8">
            {line.value.toFixed(1)}
          </text>
        </g>
      ))}

      <path d={areaPath} fill={colour} opacity="0.10" />
      <path d={linePath} fill="none" stroke={colour} strokeWidth="2.5"
        strokeLinejoin="round" strokeLinecap="round" />

      <circle cx={xFor(times[times.length - 1])} cy={yFor(lastPoint.value)}
        r="4" fill={colour} />
      <text x={xFor(times[times.length - 1])} y={yFor(lastPoint.value) - 10}
        textAnchor="middle" fontSize="12" fontWeight="700" fill={colour}>
        {lastPoint.value} {unit}
      </text>

      <text x={padding.left} y={height - 8} fontSize="11" fill="#94a3b8">
        {formatTime(points[0].receivedAt)}
      </text>
      <text x={width - padding.right} y={height - 8} textAnchor="end"
        fontSize="11" fill="#94a3b8">
        {formatTime(lastPoint.receivedAt)}
      </text>
    </svg>
  );
}

function ReadingCards({ readings }) {
  if (!readings.length) {
    return (
      <div className="empty-state">
        <h2>No sensor readings yet</h2>
        <p>Start the sensor simulator in another terminal. The backend will store MQTT messages in MongoDB and these cards will update automatically.</p>
      </div>
    );
  }

  return (
    <div className="card-grid">
      {readings.map((reading) => {
        const meta = metaFor(reading.sensorType);
        return (
          <article className="reading-card" key={reading.sensorType}
            style={{ borderTopColor: meta.colour }}>
            <p className="reading-card-label">{meta.label}</p>
            <p className="reading-card-value" style={{ color: meta.colour }}>
              {reading.value}<span> {reading.unit}</span>
            </p>
            <p className="reading-card-device">{reading.deviceId}</p>
            <p className="reading-card-time">Updated {formatTime(reading.receivedAt)}</p>
          </article>
        );
      })}
    </div>
  );
}

function ReadingTable({ readings }) {
  if (!readings.length) return null;

  return (
    <div className="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Sensor type</th>
            <th>Value</th>
            <th>Device</th>
            <th>Topic</th>
            <th>Observed</th>
            <th>Stored</th>
          </tr>
        </thead>
        <tbody>
          {readings.map((reading) => (
            <tr key={reading.sensorType}>
              <td><span className={`pill ${reading.sensorType}`}>{reading.sensorType}</span></td>
              <td className="value">{reading.value} <span>{reading.unit}</span></td>
              <td>{reading.deviceId}</td>
              <td className="topic">{reading.topic}</td>
              <td>{formatTime(reading.observedAt)}</td>
              <td>{formatTime(reading.receivedAt)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function App() {
  const [readings, setReadings] = useState([]);
  const [series, setSeries] = useState([]);
  const [sensorTypes, setSensorTypes] = useState([]);
  const [runtime, setRuntime] = useState(null);
  const [lastSnapshot, setLastSnapshot] = useState(null);
  const [connectionState, setConnectionState] = useState("connecting");
  const [error, setError] = useState("");

  // Filter controls.
  const [selectedSensor, setSelectedSensor] = useState("temperature");
  const [windowMinutes, setWindowMinutes] = useState(5);

  useEffect(() => {
    const source = new EventSource(`${apiBase}/api/stream`);

    source.addEventListener("open", () => {
      setConnectionState("connected");
      setError("");
    });

    source.addEventListener("snapshot", (event) => {
      const payload = JSON.parse(event.data);
      setReadings(payload.readings || []);
      setSeries(payload.series || []);
      setSensorTypes(payload.sensorTypes || []);
      setRuntime(payload.runtime || null);
      setLastSnapshot(payload.sentAt);
      setConnectionState("connected");
    });

    source.addEventListener("stream-error", (event) => {
      const payload = JSON.parse(event.data);
      setError(payload.message || "The backend could not send the latest snapshot.");
    });

    source.addEventListener("error", () => {
      setConnectionState("reconnecting");
      setError("The dashboard is waiting for the backend event stream.");
    });

    return () => source.close();
  }, []);

  async function refreshNow() {
    const response = await fetch(`${apiBase}/api/readings/latest`);
    const payload = await response.json();
    setReadings(payload.data || []);
    setLastSnapshot(new Date().toISOString());
  }

  // Apply the sensor-type and time-window filters to the series in the browser.
  const chartPoints = useMemo(() => {
    const cutoff = Date.now() - windowMinutes * 60 * 1000;
    return series
      .filter((row) => row.sensorType === selectedSensor)
      .filter((row) => new Date(row.receivedAt).getTime() >= cutoff)
      .sort((a, b) => new Date(a.receivedAt) - new Date(b.receivedAt));
  }, [series, selectedSensor, windowMinutes]);

  const metrics = useMemo(() => {
    return {
      latestCount: readings.length,
      storedMessages: runtime?.storedMessages || 0,
      receivedMessages: runtime?.receivedMessages || 0
    };
  }, [readings, runtime]);

  const meta = metaFor(selectedSensor);
  const availableSensors = sensorTypes.length ? sensorTypes : Object.keys(SENSOR_META);

  return (
    <main className="page-shell">
      <section className="hero">
        <div>
          <p className="eyebrow">Week 7 · MQTT + MongoDB + React</p>
          <h1>IoT Telemetry Dashboard</h1>
          <p className="hero-copy">
            The backend subscribes to MQTT topics, stores each sensor message in MongoDB, and streams a fresh snapshot to this React interface every few seconds. The chart and table below update on their own.
          </p>
        </div>
        <div className={`status-card ${connectionState}`}>
          <span>{connectionState}</span>
          <p>Live stream</p>
        </div>
      </section>

      <section className="metrics">
        <article>
          <strong>{metrics.latestCount}</strong>
          <span>Latest sensor types</span>
        </article>
        <article>
          <strong>{metrics.receivedMessages}</strong>
          <span>MQTT messages received</span>
        </article>
        <article>
          <strong>{metrics.storedMessages}</strong>
          <span>MongoDB documents stored</span>
        </article>
      </section>

      <ReadingCards readings={readings} />

      <section className="panel">
        <div className="panel-header">
          <div>
            <p className="eyebrow">Live chart</p>
            <h2>{meta.label} over time</h2>
            <p>Showing the last {windowMinutes} minute(s) · {chartPoints.length} point(s)</p>
          </div>
          <div className="controls">
            <label>
              Sensor
              <select value={selectedSensor}
                onChange={(event) => setSelectedSensor(event.target.value)}>
                {availableSensors.map((type) => (
                  <option key={type} value={type}>{metaFor(type).label}</option>
                ))}
              </select>
            </label>
            <label>
              Time window
              <select value={windowMinutes}
                onChange={(event) => setWindowMinutes(Number(event.target.value))}>
                <option value={1}>Last 1 minute</option>
                <option value={5}>Last 5 minutes</option>
                <option value={15}>Last 15 minutes</option>
                <option value={60}>Last 60 minutes</option>
              </select>
            </label>
          </div>
        </div>

        {error ? <p className="notice">{error}</p> : null}
        <LineChart points={chartPoints} colour={meta.colour} unit={meta.unit} />
      </section>

      <section className="panel">
        <div className="panel-header">
          <div>
            <p className="eyebrow">Latest MongoDB snapshot</p>
            <h2>Current sensor readings</h2>
            <p>Last frontend update: {formatDateTime(lastSnapshot)}</p>
          </div>
          <button type="button" onClick={refreshNow}>Fetch now</button>
        </div>
        <ReadingTable readings={readings} />
      </section>

      <footer className="page-footer">
        <p>Week 7 IoT MQTT Dashboard · Copyright (c) 2026 Dr Shuo Ding · Licensed under AGPL-3.0-or-later.</p>
      </footer>
    </main>
  );
}

createRoot(document.getElementById("root")).render(<App />);
