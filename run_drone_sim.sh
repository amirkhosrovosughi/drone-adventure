#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PX4_DIR="${ROOT_DIR}/PX4-Autopilot"
MODEL="${1:-gz_x500_depth}"
WORLD="${2:-default}"
XRCE_PORT="${XRCE_PORT:-8888}"

if ! command -v gz >/dev/null 2>&1; then
  echo "[ERROR] 'gz' command not found. Install Gazebo Garden/Fortress and try again."
  exit 1
fi

if [[ ! -d "${PX4_DIR}" ]]; then
  echo "[ERROR] PX4 directory not found at: ${PX4_DIR}"
  exit 1
fi

cd "${PX4_DIR}"

if [[ ! -f "build/px4_sitl_default/rootfs/gz_env.sh" ]]; then
  echo "[INFO] PX4 build artifacts missing; running initial build setup..."
  make px4_sitl >/dev/null
fi

source build/px4_sitl_default/rootfs/gz_env.sh

WORLD_FILE="${PX4_GZ_WORLDS}/${WORLD}.sdf"
if [[ ! -f "${WORLD_FILE}" ]]; then
  echo "[ERROR] World file not found: ${WORLD_FILE}"
  exit 1
fi

world_is_running() {
  gz topic -l 2>/dev/null | grep -q "^/world/${WORLD}/clock$"
}

create_service_ready() {
  gz service -l 2>/dev/null | grep -q "^/world/${WORLD}/create$"
}

if world_is_running; then
  echo "[INFO] Gazebo world '${WORLD}' already running."
else
  echo "[INFO] Starting Gazebo server with ${WORLD_FILE}"
  gz sim --verbose=1 -r -s "${WORLD_FILE}" >/tmp/gz_${WORLD}_server.log 2>&1 &
  GZ_SERVER_PID=$!
  echo "[INFO] Gazebo server PID: ${GZ_SERVER_PID}"

  # Start GUI unless already running.
  if ! pgrep -af "gz sim -g" >/dev/null 2>&1; then
    gz sim -g >/tmp/gz_${WORLD}_gui.log 2>&1 &
    echo "[INFO] Gazebo GUI started."
  fi
fi

echo "[INFO] Waiting for '/world/${WORLD}/create' service..."
for _ in $(seq 1 120); do
  if create_service_ready; then
    echo "[INFO] Gazebo is ready."
    break
  fi
  sleep 0.5
done

if ! create_service_ready; then
  echo "[ERROR] Gazebo create service not ready after 60s."
  echo "[HINT] Check: /tmp/gz_${WORLD}_server.log"
  exit 1
fi

if command -v MicroXRCEAgent >/dev/null 2>&1; then
  if pgrep -af "MicroXRCEAgent udp4 -p ${XRCE_PORT}" >/dev/null 2>&1; then
    echo "[INFO] MicroXRCEAgent already running on UDP ${XRCE_PORT}."
  else
    echo "[INFO] Starting MicroXRCEAgent on UDP ${XRCE_PORT}."
    MicroXRCEAgent udp4 -p "${XRCE_PORT}" >/tmp/microxrce_agent_${XRCE_PORT}.log 2>&1 &
  fi
else
  echo "[WARN] MicroXRCEAgent not found in PATH; ROS2<->PX4 DDS bridge will not start from this script."
fi

echo "[INFO] Launching PX4: make px4_sitl ${MODEL}"
exec make px4_sitl "${MODEL}"
