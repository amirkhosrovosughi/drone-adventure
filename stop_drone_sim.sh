#!/usr/bin/env bash
set -euo pipefail

echo "[INFO] Stopping PX4 SITL + Gazebo processes..."

PATS=(
  "make px4_sitl"
  "/PX4-Autopilot/build/px4_sitl_default/bin/px4"
  "gz sim"
  "MicroXRCEAgent udp4 -p 8888"
)

for pat in "${PATS[@]}"; do
  pkill -f "${pat}" 2>/dev/null || true
done

# Give processes a moment to exit cleanly.
sleep 1

still_running=0
for pat in "${PATS[@]}"; do
  if pgrep -af "${pat}" >/dev/null 2>&1; then
    still_running=1
  fi
done

if [[ ${still_running} -eq 1 ]]; then
  echo "[WARN] Some processes still running, forcing stop..."
  for pat in "${PATS[@]}"; do
    pkill -9 -f "${pat}" 2>/dev/null || true
  done
  sleep 0.5
fi

if pgrep -af "gz sim|/PX4-Autopilot/build/px4_sitl_default/bin/px4|make px4_sitl|MicroXRCEAgent udp4 -p 8888" >/dev/null 2>&1; then
  echo "[WARN] Some related processes may still be running:"
  pgrep -af "gz sim|/PX4-Autopilot/build/px4_sitl_default/bin/px4|make px4_sitl|MicroXRCEAgent udp4 -p 8888" || true
  exit 1
fi

echo "[INFO] Clean stop complete. Ready for next run."
