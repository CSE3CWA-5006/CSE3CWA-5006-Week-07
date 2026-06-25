#!/usr/bin/env bash
#
# Week 7 IoT Sensor Simulator - run_ubuntu.sh
# Copyright (c) 2026 Dr Shuo Ding <shuoding@outlook.com>
# Licensed under the GNU Affero General Public License v3.0 or later
# (AGPL-3.0-or-later). See the LICENSE file.
#
# Purpose:
#   Start the sensor simulator. This program pretends to be three IoT sensors
#   (temperature, humidity, pressure) and publishes their readings to the MQTT
#   broker. It does NOT talk to the dashboard directly: both programs only meet
#   at the broker.
#
# How to run:
#   chmod +x run_ubuntu.sh
#   ./run_ubuntu.sh
#
# Requirements: Node.js 20+ and a running Mosquitto broker
# (install both with ../setup_ubuntu_services.sh first).

set -euo pipefail

echo "============================================================"
echo "Week 7 Sensor Simulator"
echo "============================================================"
echo
echo "Each simulated sensor publishes to its own MQTT topic every 5 seconds:"
echo "  temperature -> latrobe/building-a/level-2/room-204/temperature"
echo "  humidity    -> latrobe/building-a/level-2/room-204/humidity"
echo "  pressure    -> latrobe/building-a/level-2/room-204/pressure"
echo
echo "Values change smoothly (a 'random walk'), like real sensors."
echo

# Check Node.js is installed before doing anything else.
if ! command -v node >/dev/null 2>&1; then
  echo "ERROR: Node.js was not found. Install Node.js 20 LTS or newer, then retry."
  exit 1
fi

# Check npm (the Node package manager) is installed.
if ! command -v npm >/dev/null 2>&1; then
  echo "ERROR: npm was not found. Install npm before running this script."
  exit 1
fi

# Create a personal .env file from the template on first run. The .env file
# holds settings (broker URL, base topic) and is safe to edit later.
if [ ! -f .env ]; then
  echo "Creating .env from .env.example (first run)."
  cp .env.example .env
fi

# Download the Node dependencies listed in package.json (mqtt, dotenv).
# 'npm install' is safe to run repeatedly; it does nothing if already installed.
echo "Installing Node dependencies if needed..."
npm install

echo
echo "Starting the sensor simulator. Press Ctrl + C to stop."
echo "============================================================"
echo

# 'npm start' runs the "start" script in package.json: node sensor-publisher.js
npm start
