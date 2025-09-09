#!/bin/bash
# block_telemetry.sh - Block Google telemetry at network level
# Created: 2025-09-06

echo "=== Blocking Google Telemetry Traffic ==="

# Check if running as root for iptables
if [ "$EUID" -ne 0 ]; then
    echo "Note: Some operations require root. Run with sudo for full blocking."
    SUDO_PREFIX="sudo"
else
    SUDO_PREFIX=""
fi

echo "Blocking OpenTelemetry ports..."

# Block OpenTelemetry ports
$SUDO_PREFIX iptables -A OUTPUT -p tcp --dport 4317 -j DROP
$SUDO_PREFIX iptables -A OUTPUT -p tcp --dport 4318 -j DROP
$SUDO_PREFIX iptables -A OUTPUT -p udp --dport 4317 -j DROP
$SUDO_PREFIX iptables -A OUTPUT -p udp --dport 4318 -j DROP

# Block Jaeger debug interface
$SUDO_PREFIX iptables -A OUTPUT -p tcp --dport 16686 -j DROP

echo "Blocking Google telemetry endpoints..."

# Block Google telemetry endpoints (more targeted)
$SUDO_PREFIX iptables -A OUTPUT -d googleapis.com -m string --string "gemini_cli" --algo bm -j DROP
$SUDO_PREFIX iptables -A OUTPUT -d googleapis.com -m string --string "custom.googleapis" --algo bm -j DROP

# Add logging for blocked attempts (optional)
read -p "Enable logging of blocked telemetry attempts? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    $SUDO_PREFIX iptables -A OUTPUT -p tcp --dport 4317 -j LOG --log-prefix "BLOCKED_TELEMETRY_4317: "
    $SUDO_PREFIX iptables -A OUTPUT -p tcp --dport 4318 -j LOG --log-prefix "BLOCKED_TELEMETRY_4318: "
    echo "Logging enabled. Check /var/log/kern.log for blocked attempts."
fi

echo "Network-level telemetry blocking applied."

# Configuration-level blocking
echo ""
echo "Applying configuration-level blocking..."

# Create telemetry-disabled settings
mkdir -p ~/.gemini
cat > ~/.gemini/settings.json << EOF
{
  "telemetry": {
    "enabled": false,
    "target": "none",
    "collector": {
      "disabled": true
    }
  },
  "privacy": {
    "data_collection": false,
    "usage_analytics": false,
    "error_reporting": false
  }
}
EOF

echo "Created ~/.gemini/settings.json with telemetry disabled"

# Make settings read-only to prevent modification
chmod 444 ~/.gemini/settings.json
if command -v chattr >/dev/null 2>&1; then
    chattr +i ~/.gemini/settings.json 2>/dev/null && echo "Settings file protected from modification"
fi

# Environment variable blocking
echo ""
echo "Setting anti-telemetry environment variables..."

# Add to current session
export GEMINI_TELEMETRY_DISABLED=1
export OTEL_EXPORTER_OTLP_ENDPOINT=""
export OTEL_SDK_DISABLED=true
export GEMINI_ANALYTICS_DISABLED=1

# Add to ~/.bashrc if not already present
if ! grep -q "GEMINI_TELEMETRY_DISABLED" ~/.bashrc; then
    cat >> ~/.bashrc << 'EOF'

# Disable Google Gemini CLI telemetry
export GEMINI_TELEMETRY_DISABLED=1
export OTEL_EXPORTER_OTLP_ENDPOINT=""
export OTEL_SDK_DISABLED=true
export GEMINI_ANALYTICS_DISABLED=1
EOF
    echo "Added anti-telemetry variables to ~/.bashrc"
fi

# Kill any running telemetry processes
echo ""
echo "Stopping existing telemetry processes..."
pkill -f "otelcol" 2>/dev/null && echo "Killed OpenTelemetry collector"
pkill -f "jaeger" 2>/dev/null && echo "Killed Jaeger"
pkill -f "telemetry" 2>/dev/null && echo "Killed telemetry processes"

# Remove existing telemetry logs/config
if [ -d ~/.gemini ]; then
    rm -f ~/.gemini/collector-*.yaml 2>/dev/null && echo "Removed telemetry configuration"
    rm -f ~/.gemini/collector*.log 2>/dev/null && echo "Removed telemetry logs"
fi

echo ""
echo "=== Telemetry Blocking Complete ==="
echo ""
echo "Summary:"
echo "✓ Network traffic blocked (ports 4317, 4318, 16686)"
echo "✓ Configuration disabled in ~/.gemini/settings.json" 
echo "✓ Environment variables set to disable telemetry"
echo "✓ Existing telemetry processes terminated"
echo ""
echo "Test Gemini CLI functionality to ensure it still works:"
echo "  gemini 'simple test command'"
echo ""
echo "Monitor blocked attempts with:"
echo "  sudo tail -f /var/log/kern.log | grep BLOCKED_TELEMETRY"