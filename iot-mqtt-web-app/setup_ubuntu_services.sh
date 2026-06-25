#!/usr/bin/env bash
#
# Week 7 Page 2 - setup_ubuntu_services.sh
# Copyright (c) 2026 Dr Shuo Ding <shuoding@outlook.com>
# Licensed under the GNU Affero General Public License v3.0 or later
# (AGPL-3.0-or-later). Any copy, modification, or distribution must retain
# this copyright notice and remain under the AGPL. See the LICENSE file.
#
# Purpose:
#   Install and start the two background services this lab needs on Ubuntu:
#     1. Mosquitto  - the MQTT broker (listens on TCP port 1883)
#     2. MongoDB    - the database that stores sensor readings (port 27017)
#
#   This script is written for a beginner. It explains each step, checks that
#   the system is Ubuntu, and stops with a clear message if anything is wrong
#   instead of failing silently.
#
# How to run:
#   chmod +x setup_ubuntu_services.sh
#   ./setup_ubuntu_services.sh
#
#   You will be asked for your password because installing system packages
#   needs administrator (sudo) rights. That is normal and expected.

# 'set -e'  : stop the whole script immediately if any command fails.
# 'set -u'  : treat the use of an undefined variable as an error.
# 'pipefail': if any command in a pipe fails, the pipe is considered failed.
set -euo pipefail

echo "============================================================"
echo "Week 7 Page 2: Ubuntu service setup (Mosquitto + MongoDB)"
echo "============================================================"
echo
echo "This script installs and starts two local services:"
echo "  1. Mosquitto MQTT broker on port 1883"
echo "  2. MongoDB Community Edition on port 27017"
echo
echo "It must be run on Ubuntu. It uses apt (the package manager) and"
echo "systemd (the service manager)."
echo

# ---------------------------------------------------------------------------
# Step 0: sanity checks before we change anything on the machine.
# ---------------------------------------------------------------------------

# 0a. We need 'sudo' to install system packages.
if ! command -v sudo >/dev/null 2>&1; then
  echo "ERROR: 'sudo' was not found. Please run this on a standard Ubuntu system."
  exit 1
fi

# 0b. /etc/os-release describes the Linux distribution. If it is missing we
#     cannot safely detect the Ubuntu version, so we stop.
if [ ! -f /etc/os-release ]; then
  echo "ERROR: Cannot detect the operating system (/etc/os-release is missing)."
  exit 1
fi

# Load the variables from /etc/os-release (ID, VERSION_CODENAME, PRETTY_NAME...).
# shellcheck disable=SC1091
. /etc/os-release

# 0c. Confirm this is really Ubuntu. The MongoDB repository below is built for
#     specific Ubuntu releases, so running elsewhere would not be reliable.
if [ "${ID:-}" != "ubuntu" ]; then
  echo "ERROR: This teaching script is written for Ubuntu."
  echo "Detected system: ${PRETTY_NAME:-unknown}"
  exit 1
fi

echo "Detected Ubuntu release: ${PRETTY_NAME}"
echo

# ---------------------------------------------------------------------------
# Step 1: install and start the Mosquitto MQTT broker.
# ---------------------------------------------------------------------------
echo "------------------------------------------------------------"
echo "Step 1: Install the Mosquitto MQTT broker and its clients."
echo "------------------------------------------------------------"

# 'apt-get update' refreshes the list of available packages.
sudo apt-get update

# Install the broker (mosquitto), the command-line test tools
# (mosquitto-clients), and two helpers used later to add MongoDB's repository
# securely (gnupg for keys, curl for downloading).
sudo apt-get install -y mosquitto mosquitto-clients gnupg curl

# 'enable'  : start automatically on every boot.
# 'restart' : start now (and restart if it was already running).
echo "Enabling and starting Mosquitto..."
sudo systemctl enable mosquitto
sudo systemctl restart mosquitto

echo
echo "Mosquitto status (first lines only):"
# '|| true' means: even if the status command returns non-zero, do not abort.
systemctl --no-pager --full status mosquitto | sed -n '1,6p' || true
echo

# ---------------------------------------------------------------------------
# Step 2: install and start MongoDB Community Edition 8.0.
#
# MongoDB is NOT in Ubuntu's default repositories, so we add MongoDB's own
# official apt repository first. We do this securely:
#   - download MongoDB's signing key,
#   - store it as a 'keyring' file,
#   - tell apt to trust packages from MongoDB signed with that key.
# ---------------------------------------------------------------------------
echo "------------------------------------------------------------"
echo "Step 2: Install MongoDB Community Edition 8.0."
echo "------------------------------------------------------------"
echo "MongoDB 8.0 supports Ubuntu 20.04, 22.04 and 24.04 LTS."

# The Ubuntu 'codename' (focal=20.04, jammy=22.04, noble=24.04) selects the
# correct MongoDB repository line.
CODENAME="${VERSION_CODENAME:-}"
case "$CODENAME" in
  noble|jammy|focal)
    echo "Ubuntu codename detected: $CODENAME"
    ;;
  *)
    echo "ERROR: This script does not auto-configure MongoDB for Ubuntu '$CODENAME'."
    echo "Please follow MongoDB's official Ubuntu install guide for your release."
    exit 1
    ;;
esac

# Only install MongoDB if it is not already present (makes re-running safe).
if ! command -v mongod >/dev/null 2>&1; then
  echo "Adding MongoDB's official signing key..."
  # Download the key and convert it into the binary 'keyring' format apt wants.
  curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc \
    | sudo gpg --batch --yes -o /usr/share/keyrings/mongodb-server-8.0.gpg --dearmor

  echo "Adding the MongoDB 8.0 apt repository for $CODENAME..."
  echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${CODENAME}/mongodb-org/8.0 multiverse" \
    | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list >/dev/null

  # Refresh the package list so the new MongoDB packages become visible.
  sudo apt-get update
  echo "Installing the mongodb-org package..."
  sudo apt-get install -y mongodb-org
else
  echo "MongoDB ('mongod') is already installed. Skipping package installation."
fi

echo "Enabling and starting MongoDB..."
sudo systemctl enable mongod
sudo systemctl restart mongod

echo
echo "MongoDB status (first lines only):"
systemctl --no-pager --full status mongod | sed -n '1,6p' || true
echo

# ---------------------------------------------------------------------------
# Step 3: quick smoke tests so you can see both services actually respond.
# ---------------------------------------------------------------------------
echo "------------------------------------------------------------"
echo "Step 3: Quick service tests."
echo "------------------------------------------------------------"

echo "Testing the MQTT broker with a single publish..."
# Publishing a test message should return silently with no error.
if mosquitto_pub -h localhost -t week7/setup/test -m "mosquitto-ready"; then
  echo "  OK: Mosquitto accepted a test publish on port 1883."
else
  echo "  WARNING: Mosquitto test publish failed. Check 'systemctl status mosquitto'."
fi

echo "Testing MongoDB with a ping..."
# 'mongosh' is the MongoDB shell. On some installs it is a separate package.
if command -v mongosh >/dev/null 2>&1; then
  mongosh --quiet --eval 'db.runCommand({ ping: 1 })' \
    && echo "  OK: MongoDB responded to a ping on port 27017." \
    || echo "  WARNING: MongoDB ping failed. Check 'systemctl status mongod'."
else
  echo "  NOTE: 'mongosh' is not installed, so the shell ping test was skipped."
  echo "        MongoDB itself may still be running. You can install the shell"
  echo "        later with: sudo apt-get install -y mongodb-mongosh"
fi

echo
echo "============================================================"
echo "Setup complete."
echo
echo "Next steps (in two separate terminals):"
echo "  Terminal 1:  cd iot_mqtt_dashboard   && ./run_ubuntu.sh"
echo "  Terminal 2:  cd iot_sensor_simulator && ./run_ubuntu.sh"
echo
echo "Then open the dashboard at: http://localhost:5174"
echo "============================================================"
