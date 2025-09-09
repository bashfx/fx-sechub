#!/bin/bash
# capture_telemetry.sh - Capture and analyze Google telemetry data
# Created: 2025-09-06

CAPTURE_FILE="gemini_telemetry_$(date +%Y%m%d_%H%M%S).pcap"
ANALYSIS_DIR="telemetry_analysis"

echo "=== Google Telemetry Traffic Capture ==="
echo "Capture file: $CAPTURE_FILE"

# Check if running as root for tcpdump
if [ "$EUID" -ne 0 ]; then
    echo "This script requires root access for packet capture."
    echo "Run with: sudo $0"
    exit 1
fi

# Create analysis directory
mkdir -p "$ANALYSIS_DIR"

echo "Starting packet capture for telemetry traffic..."
echo "Monitoring ports: 4317 (OTLP GRPC), 4318 (OTLP HTTP), 16686 (Jaeger)"
echo "Press Ctrl+C to stop capture and analyze"

# Start packet capture in background
tcpdump -i any -w "$CAPTURE_FILE" -s 65535 \
  '(port 4317 or port 4318 or port 16686) or (host googleapis.com and port 443)' &

TCPDUMP_PID=$!

echo "Packet capture started (PID: $TCPDUMP_PID)"
echo ""
echo "Now run Gemini CLI commands in another terminal to generate telemetry:"
echo "  gemini 'test command'"
echo "  gemini --help"
echo ""
echo "Press Enter when done capturing..."
read -r

# Stop packet capture
echo "Stopping packet capture..."
kill $TCPDUMP_PID 2>/dev/null
wait $TCPDUMP_PID 2>/dev/null

# Check if any data was captured
if [ ! -f "$CAPTURE_FILE" ] || [ ! -s "$CAPTURE_FILE" ]; then
    echo "No telemetry traffic captured."
    echo "Either telemetry is already blocked, or no Gemini CLI activity occurred."
    exit 0
fi

echo ""
echo "=== Analyzing Captured Telemetry Data ==="

# Basic traffic analysis
echo "Traffic summary:" > "$ANALYSIS_DIR/traffic_summary.txt"
tcpdump -r "$CAPTURE_FILE" 2>>error.log | head -20 >> "$ANALYSIS_DIR/traffic_summary.txt"

# Extract text content for analysis
echo "Extracting readable content..."
tcpdump -r "$CAPTURE_FILE" -A | grep -E "(gemini|telemetry|googleapis|custom\.)" > "$ANALYSIS_DIR/readable_content.txt"

# Look for HTTP traffic
echo "HTTP traffic analysis:"
tcpdump -r "$CAPTURE_FILE" -A 'tcp port 443' | \
  grep -E "(POST|GET|Host:|User-Agent:|Content-Type:)" > "$ANALYSIS_DIR/http_traffic.txt"

# Look for OpenTelemetry specific content
echo "OpenTelemetry protocol analysis:"
tcpdump -r "$CAPTURE_FILE" -A 'port 4317 or port 4318' | \
  strings | grep -E "(otel|telemetry|metric|trace|log)" > "$ANALYSIS_DIR/otel_content.txt"

# Network connections summary
echo "Connection summary:"
tcpdump -r "$CAPTURE_FILE" | awk '{print $3, $5}' | sort | uniq -c | sort -nr > "$ANALYSIS_DIR/connections.txt"

echo ""
echo "=== Analysis Results ==="

# Show summary
PACKET_COUNT=$(tcpdump -r "$CAPTURE_FILE" 2>/dev/null | wc -l)
echo "Total packets captured: $PACKET_COUNT"

# Show destinations
echo ""
echo "Top destination endpoints:"
head -10 "$ANALYSIS_DIR/connections.txt"

# Check for sensitive content
echo ""
echo "Checking for potentially sensitive data..."

SENSITIVE_PATTERNS=("api.*key" "token" "secret" "password" "home" "user" "project")
for pattern in "${SENSITIVE_PATTERNS[@]}"; do
    if grep -i "$pattern" "$ANALYSIS_DIR/readable_content.txt" >/dev/null 2>&1; then
        echo "ALERT: Potential '$pattern' found in telemetry data"
    fi
done

# Show readable content sample
echo ""
echo "Sample of readable telemetry content (first 10 lines):"
head -10 "$ANALYSIS_DIR/readable_content.txt" | sed 's/api[_-]key[=:][^[:space:]]*/[API_KEY_REDACTED]/gi'

echo ""
echo "=== Full Analysis Available ==="
echo "Detailed analysis saved in: $ANALYSIS_DIR/"
echo "  - traffic_summary.txt    : General traffic overview"
echo "  - readable_content.txt   : Extracted readable content"
echo "  - http_traffic.txt       : HTTP/HTTPS traffic details"
echo "  - otel_content.txt       : OpenTelemetry protocol data"
echo "  - connections.txt        : Network connection summary"
echo ""
echo "Raw packet capture: $CAPTURE_FILE"
echo ""
echo "SECURITY NOTE: Review readable_content.txt for sensitive information"
echo "that may be transmitted to Google's servers."