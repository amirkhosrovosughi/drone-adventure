#!/usr/bin/env bash
# monitor_resources.sh
#
# Purpose:
#   Live resource monitor for robotics/simulation runs (e.g., Gazebo + PX4 + XRCE).
#   It prints current, average, and max values over time, and a final summary on Ctrl+C.
#
# What it tracks:
#   - System CPU usage
#   - System RAM usage
#   - Process-level load for commands matching: gz sim | px4 | MicroXRCEAgent
#   - GPU metrics (utilization, memory, temperature) when NVIDIA SMI is available
#
# Usage:
#   ./monitor_resources.sh          # default update interval: 2 seconds
#   ./monitor_resources.sh 1        # update every 1 second
#
# Compatibility / limitations:
#   - Requires Linux-style procfs (/proc/stat, /proc/meminfo).
#   - Uses common POSIX tools: awk, ps, grep, date, clear.
#   - GPU section is NVIDIA-specific (nvidia-smi). If unavailable, GPU metrics are skipped.
#   - Process metrics depend on command-name matching and may miss differently named binaries.
#   - This is a lightweight observer script, not a profiler; values are sampling-based.
#
# Intended environment:
#   - Linux hosts, or Linux-compatible environments (including common container/WSL setups)
#   - Best effort in other environments, but behavior is not guaranteed.

set -u -o pipefail

CPU_LIMIT_PCT="95"
RAM_LIMIT_PCT="95"
GPU_LIMIT_PCT="95"

INTERVAL="${1:-2}"
if ! [[ "$INTERVAL" =~ ^[0-9]+([.][0-9]+)?$ ]] || awk "BEGIN{exit !($INTERVAL>0)}"; then
  echo "[WARN] Invalid interval '$INTERVAL'. Using 2 seconds."
  INTERVAL="2"
fi

START_EPOCH="$(date +%s)"
SAMPLES=0
STOP_REQUESTED=0

SUM_CPU=0
MAX_CPU=0

SUM_RAM_PCT=0
MAX_RAM_PCT=0
MAX_RAM_USED_MB=0

SUM_PROC_CPU=0
MAX_PROC_CPU=0
SUM_PROC_RSS_MB=0
MAX_PROC_RSS_MB=0

GPU_AVAILABLE=0
SUM_GPU_UTIL=0
MAX_GPU_UTIL=0
SUM_GPU_MEM_PCT=0
MAX_GPU_MEM_PCT=0
MAX_GPU_MEM_USED_MB=0
SUM_GPU_MEM_UTIL=0
MAX_GPU_MEM_UTIL=0
SUM_GPU_TEMP=0
MAX_GPU_TEMP=0

if command -v nvidia-smi >/dev/null 2>&1; then
  NVIDIA_SMI_BIN="$(command -v nvidia-smi)"
elif [[ -x "/usr/lib/wsl/lib/nvidia-smi" ]]; then
  NVIDIA_SMI_BIN="/usr/lib/wsl/lib/nvidia-smi"
else
  NVIDIA_SMI_BIN=""
fi

if [[ -n "${NVIDIA_SMI_BIN}" ]]; then
  GPU_AVAILABLE=1
fi

format_duration() {
  local seconds="$1"
  local h=$((seconds / 3600))
  local m=$(((seconds % 3600) / 60))
  local s=$((seconds % 60))
  printf "%02d:%02d:%02d" "$h" "$m" "$s"
}

read_cpu_times() {
  awk '/^cpu / {print $2,$3,$4,$5,$6,$7,$8,$9}' /proc/stat
}

read_ram_stats() {
  local total avail used pct
  read -r total avail < <(awk '/MemTotal/ {t=$2} /MemAvailable/ {a=$2} END {print int(t/1024), int(a/1024)}' /proc/meminfo)
  used=$((total - avail))
  if [[ "$total" -gt 0 ]]; then
    pct="$(awk "BEGIN {printf \"%.2f\", (100.0*$used)/$total}")"
  else
    pct="0"
  fi
  echo "$used $total $pct"
}

read_process_stats() {
  ps -eo pcpu,rss,cmd --no-headers | awk '
    /gz sim|px4|MicroXRCEAgent/ && $0 !~ /awk/ {
      cpu += $1;
      rss += $2;
    }
    END {
      printf "%.2f %.2f", cpu, rss/1024.0;
    }
  '
}

read_gpu_stats() {
  if [[ "$GPU_AVAILABLE" -eq 0 ]]; then
    echo "NA NA NA NA NA"
    return
  fi

  local line util mem_util mem_used mem_total temp mem_pct
  line="$(${NVIDIA_SMI_BIN} --query-gpu=utilization.gpu,utilization.memory,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -n 1)"

  if [[ -z "$line" ]]; then
    echo "NA NA NA NA NA"
    return
  fi

  IFS=',' read -r util mem_util mem_used mem_total temp <<< "$line"
  util="$(echo "$util" | xargs)"
  mem_util="$(echo "$mem_util" | xargs)"
  mem_used="$(echo "$mem_used" | xargs)"
  mem_total="$(echo "$mem_total" | xargs)"
  temp="$(echo "$temp" | xargs)"

  if [[ "$mem_total" =~ ^[0-9]+([.][0-9]+)?$ ]] && awk "BEGIN{exit !($mem_total>0)}"; then
    mem_pct="$(awk "BEGIN {printf \"%.2f\", (100.0*$mem_used)/$mem_total}")"
  else
    mem_pct="NA"
  fi

  echo "$util $mem_util $mem_used $mem_total $temp $mem_pct"
}

on_stop() {
  STOP_REQUESTED=1
}

trap on_stop INT TERM

read -r PREV_USER PREV_NICE PREV_SYSTEM PREV_IDLE PREV_IOWAIT PREV_IRQ PREV_SOFTIRQ PREV_STEAL < <(read_cpu_times)
PREV_TOTAL=$((PREV_USER + PREV_NICE + PREV_SYSTEM + PREV_IDLE + PREV_IOWAIT + PREV_IRQ + PREV_SOFTIRQ + PREV_STEAL))
PREV_IDLE_ALL=$((PREV_IDLE + PREV_IOWAIT))

while [[ "$STOP_REQUESTED" -eq 0 ]]; do
  sleep "$INTERVAL" || true
  [[ "$STOP_REQUESTED" -eq 1 ]] && break

  read -r USER NICE SYSTEM IDLE IOWAIT IRQ SOFTIRQ STEAL < <(read_cpu_times)
  TOTAL=$((USER + NICE + SYSTEM + IDLE + IOWAIT + IRQ + SOFTIRQ + STEAL))
  IDLE_ALL=$((IDLE + IOWAIT))

  DIFF_TOTAL=$((TOTAL - PREV_TOTAL))
  DIFF_IDLE=$((IDLE_ALL - PREV_IDLE_ALL))

  if [[ "$DIFF_TOTAL" -gt 0 ]]; then
    CPU_PCT="$(awk "BEGIN {printf \"%.2f\", 100.0*($DIFF_TOTAL-$DIFF_IDLE)/$DIFF_TOTAL}")"
  else
    CPU_PCT="0"
  fi

  PREV_TOTAL=$TOTAL
  PREV_IDLE_ALL=$IDLE_ALL

  read -r RAM_USED_MB RAM_TOTAL_MB RAM_PCT < <(read_ram_stats)
  read -r PROC_CPU_PCT PROC_RSS_MB < <(read_process_stats)
  read -r GPU_UTIL GPU_MEM_UTIL GPU_MEM_USED GPU_MEM_TOTAL GPU_TEMP GPU_MEM_PCT < <(read_gpu_stats)

  SAMPLES=$((SAMPLES + 1))

  SUM_CPU="$(awk "BEGIN {printf \"%.6f\", $SUM_CPU + $CPU_PCT}")"
  MAX_CPU="$(awk "BEGIN {printf \"%.2f\", ($CPU_PCT > $MAX_CPU ? $CPU_PCT : $MAX_CPU)}")"

  SUM_RAM_PCT="$(awk "BEGIN {printf \"%.6f\", $SUM_RAM_PCT + $RAM_PCT}")"
  MAX_RAM_PCT="$(awk "BEGIN {printf \"%.2f\", ($RAM_PCT > $MAX_RAM_PCT ? $RAM_PCT : $MAX_RAM_PCT)}")"
  MAX_RAM_USED_MB=$(( RAM_USED_MB > MAX_RAM_USED_MB ? RAM_USED_MB : MAX_RAM_USED_MB ))

  SUM_PROC_CPU="$(awk "BEGIN {printf \"%.6f\", $SUM_PROC_CPU + $PROC_CPU_PCT}")"
  MAX_PROC_CPU="$(awk "BEGIN {printf \"%.2f\", ($PROC_CPU_PCT > $MAX_PROC_CPU ? $PROC_CPU_PCT : $MAX_PROC_CPU)}")"
  SUM_PROC_RSS_MB="$(awk "BEGIN {printf \"%.6f\", $SUM_PROC_RSS_MB + $PROC_RSS_MB}")"
  MAX_PROC_RSS_MB="$(awk "BEGIN {printf \"%.2f\", ($PROC_RSS_MB > $MAX_PROC_RSS_MB ? $PROC_RSS_MB : $MAX_PROC_RSS_MB)}")"

  if [[ "$GPU_AVAILABLE" -eq 1 ]] && [[ "$GPU_UTIL" != "NA" ]]; then
    SUM_GPU_UTIL="$(awk "BEGIN {printf \"%.6f\", $SUM_GPU_UTIL + $GPU_UTIL}")"
    MAX_GPU_UTIL="$(awk "BEGIN {printf \"%.2f\", ($GPU_UTIL > $MAX_GPU_UTIL ? $GPU_UTIL : $MAX_GPU_UTIL)}")"

    if [[ "$GPU_MEM_PCT" != "NA" ]]; then
      SUM_GPU_MEM_PCT="$(awk "BEGIN {printf \"%.6f\", $SUM_GPU_MEM_PCT + $GPU_MEM_PCT}")"
      MAX_GPU_MEM_PCT="$(awk "BEGIN {printf \"%.2f\", ($GPU_MEM_PCT > $MAX_GPU_MEM_PCT ? $GPU_MEM_PCT : $MAX_GPU_MEM_PCT)}")"
    fi

    SUM_GPU_MEM_UTIL="$(awk "BEGIN {printf \"%.6f\", $SUM_GPU_MEM_UTIL + $GPU_MEM_UTIL}")"
    MAX_GPU_MEM_UTIL="$(awk "BEGIN {printf \"%.2f\", ($GPU_MEM_UTIL > $MAX_GPU_MEM_UTIL ? $GPU_MEM_UTIL : $MAX_GPU_MEM_UTIL)}")"

    SUM_GPU_TEMP="$(awk "BEGIN {printf \"%.6f\", $SUM_GPU_TEMP + $GPU_TEMP}")"
    MAX_GPU_TEMP="$(awk "BEGIN {printf \"%.2f\", ($GPU_TEMP > $MAX_GPU_TEMP ? $GPU_TEMP : $MAX_GPU_TEMP)}")"

    if [[ "$GPU_MEM_USED" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
      MAX_GPU_MEM_USED_MB="$(awk "BEGIN {printf \"%.2f\", ($GPU_MEM_USED > $MAX_GPU_MEM_USED_MB ? $GPU_MEM_USED : $MAX_GPU_MEM_USED_MB)}")"
    fi
  fi

  AVG_CPU="$(awk "BEGIN {printf \"%.2f\", $SUM_CPU/$SAMPLES}")"
  AVG_RAM_PCT="$(awk "BEGIN {printf \"%.2f\", $SUM_RAM_PCT/$SAMPLES}")"
  AVG_PROC_CPU="$(awk "BEGIN {printf \"%.2f\", $SUM_PROC_CPU/$SAMPLES}")"
  AVG_PROC_RSS_MB="$(awk "BEGIN {printf \"%.2f\", $SUM_PROC_RSS_MB/$SAMPLES}")"

  NOW_EPOCH="$(date +%s)"
  ELAPSED="$(format_duration $((NOW_EPOCH - START_EPOCH)))"

  clear
  echo "=== monitor_resources.sh ==="
  echo "Elapsed: ${ELAPSED} | Interval: ${INTERVAL}s | Samples: ${SAMPLES}"
  echo
  echo "[System CPU + RAM]"
  printf "CPU util        current: %6.2f%%   avg: %6.2f%%   max: %6.2f%%\n" "$CPU_PCT" "$AVG_CPU" "$MAX_CPU"
  printf "RAM util        current: %6.2f%%   avg: %6.2f%%   max: %6.2f%%\n" "$RAM_PCT" "$AVG_RAM_PCT" "$MAX_RAM_PCT"
  printf "RAM used        current: %6d MB   max: %6d MB   total: %6d MB\n" "$RAM_USED_MB" "$MAX_RAM_USED_MB" "$RAM_TOTAL_MB"
  echo
  echo "[Gazebo/PX4/MicroXRCEAgent process load]"
  printf "Proc CPU sum    current: %6.2f%%   avg: %6.2f%%   max: %6.2f%%\n" "$PROC_CPU_PCT" "$AVG_PROC_CPU" "$MAX_PROC_CPU"
  printf "Proc RSS sum    current: %6.2f MB avg: %6.2f MB max: %6.2f MB\n" "$PROC_RSS_MB" "$AVG_PROC_RSS_MB" "$MAX_PROC_RSS_MB"

  echo
  echo "[GPU]"
  if [[ "$GPU_AVAILABLE" -eq 1 ]] && [[ "$GPU_UTIL" != "NA" ]]; then
    AVG_GPU_UTIL="$(awk "BEGIN {printf \"%.2f\", $SUM_GPU_UTIL/$SAMPLES}")"
    AVG_GPU_MEM_UTIL="$(awk "BEGIN {printf \"%.2f\", $SUM_GPU_MEM_UTIL/$SAMPLES}")"
    AVG_GPU_TEMP="$(awk "BEGIN {printf \"%.2f\", $SUM_GPU_TEMP/$SAMPLES}")"

    if [[ "$SUM_GPU_MEM_PCT" != "0" ]] || [[ "$GPU_MEM_PCT" != "NA" ]]; then
      AVG_GPU_MEM_PCT="$(awk "BEGIN {printf \"%.2f\", $SUM_GPU_MEM_PCT/$SAMPLES}")"
    else
      AVG_GPU_MEM_PCT="NA"
    fi

    printf "GPU util        current: %6s%%   avg: %6s%%   max: %6s%%\n" "$GPU_UTIL" "$AVG_GPU_UTIL" "$MAX_GPU_UTIL"
    printf "GPU mem util    current: %6s%%   avg: %6s%%   max: %6s%%\n" "$GPU_MEM_UTIL" "$AVG_GPU_MEM_UTIL" "$MAX_GPU_MEM_UTIL"
    printf "GPU mem used    current: %6s MB  max: %6s MB  total: %6s MB\n" "$GPU_MEM_USED" "$MAX_GPU_MEM_USED_MB" "$GPU_MEM_TOTAL"
    printf "GPU mem pct     current: %6s%%   avg: %6s%%   max: %6s%%\n" "$GPU_MEM_PCT" "$AVG_GPU_MEM_PCT" "$MAX_GPU_MEM_PCT"
    printf "GPU temp        current: %6s C   avg: %6s C   max: %6s C\n" "$GPU_TEMP" "$AVG_GPU_TEMP" "$MAX_GPU_TEMP"
  else
    echo "GPU metrics unavailable (nvidia-smi not found or not reporting)."
  fi

  echo
  echo "Press Ctrl+C to stop and print final summary."
done

END_EPOCH="$(date +%s)"
TOTAL_ELAPSED="$(format_duration $((END_EPOCH - START_EPOCH)))"

if [[ "$SAMPLES" -gt 0 ]]; then
  AVG_CPU="$(awk "BEGIN {printf \"%.2f\", $SUM_CPU/$SAMPLES}")"
  AVG_RAM_PCT="$(awk "BEGIN {printf \"%.2f\", $SUM_RAM_PCT/$SAMPLES}")"
  AVG_PROC_CPU="$(awk "BEGIN {printf \"%.2f\", $SUM_PROC_CPU/$SAMPLES}")"
  AVG_PROC_RSS_MB="$(awk "BEGIN {printf \"%.2f\", $SUM_PROC_RSS_MB/$SAMPLES}")"
else
  AVG_CPU="0"
  AVG_RAM_PCT="0"
  AVG_PROC_CPU="0"
  AVG_PROC_RSS_MB="0"
fi


echo
echo "=== Final Resource Summary ==="
echo "Duration: ${TOTAL_ELAPSED}"
echo "Samples:  ${SAMPLES}"
echo
printf "System CPU util   avg: %6.2f%%   max: %6.2f%%\n" "$AVG_CPU" "$MAX_CPU"
printf "System RAM util   avg: %6.2f%%   max: %6.2f%%\n" "$AVG_RAM_PCT" "$MAX_RAM_PCT"
printf "System RAM used   max: %6d MB\n" "$MAX_RAM_USED_MB"
echo
printf "Proc CPU sum      avg: %6.2f%%   max: %6.2f%%\n" "$AVG_PROC_CPU" "$MAX_PROC_CPU"
printf "Proc RSS sum      avg: %6.2f MB max: %6.2f MB\n" "$AVG_PROC_RSS_MB" "$MAX_PROC_RSS_MB"

if [[ "$GPU_AVAILABLE" -eq 1 ]] && [[ "$SAMPLES" -gt 0 ]]; then
  AVG_GPU_UTIL="$(awk "BEGIN {printf \"%.2f\", $SUM_GPU_UTIL/$SAMPLES}")"
  AVG_GPU_MEM_UTIL="$(awk "BEGIN {printf \"%.2f\", $SUM_GPU_MEM_UTIL/$SAMPLES}")"
  AVG_GPU_TEMP="$(awk "BEGIN {printf \"%.2f\", $SUM_GPU_TEMP/$SAMPLES}")"
  if [[ "$SUM_GPU_MEM_PCT" != "0" ]]; then
    AVG_GPU_MEM_PCT="$(awk "BEGIN {printf \"%.2f\", $SUM_GPU_MEM_PCT/$SAMPLES}")"
  else
    AVG_GPU_MEM_PCT="NA"
  fi

  echo
  printf "GPU util          avg: %6s%%   max: %6s%%\n" "$AVG_GPU_UTIL" "$MAX_GPU_UTIL"
  printf "GPU mem util      avg: %6s%%   max: %6s%%\n" "$AVG_GPU_MEM_UTIL" "$MAX_GPU_MEM_UTIL"
  printf "GPU mem used      max: %6s MB\n" "$MAX_GPU_MEM_USED_MB"
  printf "GPU mem pct       avg: %6s%%   max: %6s%%\n" "$AVG_GPU_MEM_PCT" "$MAX_GPU_MEM_PCT"
  printf "GPU temp          avg: %6s C   max: %6s C\n" "$AVG_GPU_TEMP" "$MAX_GPU_TEMP"
fi

echo
echo "[Limit Alerts]"
HIT_ANY_LIMIT=0

if awk "BEGIN{exit !($MAX_CPU >= $CPU_LIMIT_PCT)}"; then
  echo "[ALERT] System CPU reached limit (max ${MAX_CPU}% >= ${CPU_LIMIT_PCT}%)."
  HIT_ANY_LIMIT=1
fi

if awk "BEGIN{exit !($MAX_RAM_PCT >= $RAM_LIMIT_PCT)}"; then
  echo "[ALERT] System RAM reached limit (max ${MAX_RAM_PCT}% >= ${RAM_LIMIT_PCT}%)."
  HIT_ANY_LIMIT=1
fi

if [[ "$GPU_AVAILABLE" -eq 1 ]] && [[ "$SAMPLES" -gt 0 ]]; then
  if awk "BEGIN{exit !($MAX_GPU_UTIL >= $GPU_LIMIT_PCT)}"; then
    echo "[ALERT] GPU compute reached limit (max ${MAX_GPU_UTIL}% >= ${GPU_LIMIT_PCT}%)."
    HIT_ANY_LIMIT=1
  fi

  if [[ "$MAX_GPU_MEM_PCT" != "0" ]] && [[ "$MAX_GPU_MEM_PCT" != "NA" ]] && awk "BEGIN{exit !($MAX_GPU_MEM_PCT >= $GPU_LIMIT_PCT)}"; then
    echo "[ALERT] GPU memory reached limit (max ${MAX_GPU_MEM_PCT}% >= ${GPU_LIMIT_PCT}%)."
    HIT_ANY_LIMIT=1
  fi
fi

if [[ "$HIT_ANY_LIMIT" -eq 0 ]]; then
  echo "No CPU/RAM/GPU limit reached."
fi
