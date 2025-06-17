#!/bin/bash
# move-ct-bridge.sh
# Usage: ./move-ct-bridge.sh <CTID>
set -euo pipefail

CT="${1:?Usage: $0 <CTID>}"
BRIDGE="ovsbr0"


echo "🔁 Updating network interfaces..."
# Safely extract net* lines; skip if none defined
mapfile -t nets < <(pct config "$CT" | grep -E '^net[0-9]+:' || true)

if [ "${#nets[@]}" -eq 0 ]; then
  echo "⚠️ No network interfaces defined for container $CT."
else
  for line in "${nets[@]}"; do
    netkey="${line%%:*}"  # e.g., net0
    cfg="${line#*: }"     # rest of line
    newcfg="${cfg//bridge=[^,]*/bridge=$BRIDGE}"
    pct set "$CT" -"${netkey}" "$newcfg"
    echo "• Updated $netkey: $newcfg"
  done
fi

echo "🎬 Starting container $CT..."
pct start "$CT"

echo "✅ Verifying config..."
pct config "$CT" | grep '^net' || {
  echo "⚠️ No net entries found post-update!"
  exit 1
}

echo "🌐 Testing connectivity..."
gw=$(pct config "$CT" | grep '^net0:' | grep -o 'gw=[^,]*' | cut -d= -f2 || true)
if [ -n "${gw:-}" ]; then
  if pct exec "$CT" -- ping -c2 "$gw" >/dev/null; then
    echo "✔️ Gateway $gw is reachable"
  else
    echo "❌ Unable to reach gateway $gw"
  fi
else
  echo "⚠️ No gateway found in net0."
fi

echo "✅ Done. Container $CT is now on bridge $BRIDGE."
