#!/bin/bash

# ─────────────────────────────────────────────
#   GHTUN WARZONE - Auto Startup Script
# ─────────────────────────────────────────────

# ── 1. Get CODESPACE_NAME reliably ───────────
#    sudo strips env vars, so we read from multiple sources
if [ -z "$CODESPACE_NAME" ]; then
  # Try reading from /proc of parent process environment
  CODESPACE_NAME=$(cat /proc/1/environ 2>/dev/null | tr '\0' '\n' | grep '^CODESPACE_NAME=' | cut -d= -f2-)
fi
if [ -z "$CODESPACE_NAME" ]; then
  # Try the codespace hosts file hint
  CODESPACE_NAME=$(hostname -f 2>/dev/null | sed 's/\.internal$//' | head -1)
fi

# If still empty, abort with a clear message
if [ -z "$CODESPACE_NAME" ]; then
  echo "❌ ERROR: CODESPACE_NAME is empty!"
  echo "   Try running: sudo -E bash /etc/start.sh"
  exit 1
fi

# ── 2. Build SNI from Codespace name ─────────
SNI="${CODESPACE_NAME}-443.app.github.dev"

# ── 3. Generate fresh UUID every run ─────────
UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())")

# ── 4. Write Xray config ─────────────────────
#    GitHub Codespace is the TLS terminator.
#    Xray listens plain WS on 443 internally.
cat > /etc/config.json << XRAY_EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": 443,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "${UUID}", "level": 0 }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/live-chat"
        }
      }
    }
  ],
  "outbounds": [{ "protocol": "freedom", "settings": {} }]
}
XRAY_EOF

# ── 5. Stop old Xray, start fresh ────────────
pkill -f "xray" 2>/dev/null || true
sleep 1
nohup /usr/local/bin/xray -c /etc/config.json > /tmp/xray.log 2>&1 &
XRAY_PID=$!
sleep 2

# Verify Xray started
if ! kill -0 "$XRAY_PID" 2>/dev/null; then
  echo "❌ Xray failed to start! Log:"
  cat /tmp/xray.log
  exit 1
fi

# ── 6. Date tag ───────────────────────────────
DATE_TAG=$(date +%Y%m%d)

# ── 7. IP list ────────────────────────────────
IPS=("50.7.87.4" "50.7.87.2" "142.54.178.211" "50.7.87.5" "204.12.196.34")

# ── 8. Print output ───────────────────────────
echo ""
echo "=================================================="
echo "  🚀  GHTUN WARZONE — VPN CONFIG PANEL"
echo "=================================================="
echo "  UUID : ${UUID}"
echo "  SNI  : ${SNI}"
echo "=================================================="
echo ""

# GitHub domain config
echo "--------------------------------------------------"
echo "  🌐  GitHub Domain"
echo "--------------------------------------------------"
echo ""
echo "vless://${UUID}@${SNI}:443?encryption=none&security=tls&sni=${SNI}&insecure=0&allowInsecure=0&type=ws&path=%2Flive-chat#ghtun-ws"
echo ""

# IP configs
echo "--------------------------------------------------"
echo "  📡  Direct IP Configs (Lower Ping)"
echo "--------------------------------------------------"
echo ""
for IP in "${IPS[@]}"; do
  echo "  🔹 ${IP}"
  echo "vless://${UUID}@${IP}:443?encryption=none&security=tls&sni=${SNI}&insecure=0&allowInsecure=0&type=ws&path=%2Flive-chat#ghtun-ws"
  echo ""
done

echo "--------------------------------------------------"
echo "  ✅ Xray PID: ${XRAY_PID} | Log: /tmp/xray.log"
echo "--------------------------------------------------"
echo ""
