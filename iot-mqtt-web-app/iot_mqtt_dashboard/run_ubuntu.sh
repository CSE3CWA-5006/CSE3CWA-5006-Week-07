#!/usr/bin/env bash
#
# Week 7 IoT MQTT Dashboard - run_ubuntu.sh
# Copyright (c) 2026 Dr Shuo Ding <shuoding@outlook.com>
# Licensed under the GNU Affero General Public License v3.0 or later
# (AGPL-3.0-or-later). See the LICENSE file.
#
# Purpose:
#   Start BOTH halves of the dashboard at once:
#     1. the Express backend (subscribes to MQTT, stores readings in MongoDB,
#        and serves the API + live event stream) on http://localhost:4100
#     2. the React frontend (the web page you look at) on http://localhost:5174
#
# How to run:
#   chmod +x run_ubuntu.sh
#   ./run_ubuntu.sh
#
# Requirements: Node.js 20+, plus running Mosquitto and MongoDB services
# (install all of these with ../setup_ubuntu_services.sh first).

set -euo pipefail

echo "============================================================"
echo "Week 7 IoT MQTT Dashboard (backend + frontend)"
echo "============================================================"
echo
echo "Backend  : subscribes to MQTT, writes to MongoDB, serves the API."
echo "Frontend : a React page that shows live charts and tables."
echo
echo "The sensor simulator is a separate program. Start it in another"
echo "terminal with: cd ../iot_sensor_simulator && ./run_ubuntu.sh"
echo

# Make sure Node.js and npm are available.
if ! command -v node >/dev/null 2>&1; then
  echo "ERROR: Node.js was not found. Install Node.js 20 LTS or newer, then retry."
  exit 1
fi
if ! command -v npm >/dev/null 2>&1; then
  echo "ERROR: npm was not found. Install npm before running this script."
  exit 1
fi

# Create the backend and frontend .env files from their templates on first run.
if [ ! -f server/.env ]; then
  echo "Creating server/.env from server/.env.example (first run)."
  cp server/.env.example server/.env
fi
if [ ! -f client/.env ]; then
  echo "Creating client/.env from client/.env.example (first run)."
  cp client/.env.example client/.env
fi

# Install dependencies for each part. '--prefix' runs npm inside that folder.
echo "Installing backend dependencies..."
npm --prefix server install

echo "Installing frontend dependencies..."
npm --prefix client install

echo
echo "Starting backend on  http://localhost:4100"
echo "Starting frontend on http://localhost:5174"
echo
echo "Useful backend test URLs:"
echo "  http://localhost:4100/api/health"
echo "  http://localhost:4100/api/readings/latest"
echo "  http://localhost:4100/api/readings/series?sensorType=temperature&minutes=5"
echo
echo "Press Ctrl + C to stop both programs."
echo "============================================================"
echo

# Start the backend in the background and remember its process id (PID).
npm --prefix server run dev &
SERVER_PID=$!

# Start the frontend in the background and remember its PID.
# '--host 0.0.0.0' lets you open the page from another device on your network.
npm --prefix client run dev -- --host 0.0.0.0 &
CLIENT_PID=$!

# cleanup() stops both background programs when this script exits or you press
# Ctrl + C, so you are never left with orphaned processes holding the ports.
cleanup() {
  echo
  echo "Stopping dashboard processes..."
  kill "$SERVER_PID" "$CLIENT_PID" 2>/dev/null || true
}

# Run cleanup() on normal EXIT, on Ctrl + C (INT) and on termination (TERM).
trap cleanup EXIT INT TERM

# 'wait' keeps this script alive while the two background programs run.
wait
