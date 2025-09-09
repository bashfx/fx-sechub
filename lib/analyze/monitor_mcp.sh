#!/bin/bash
# monitor_mcp.sh - Monitor MCP (Model Context Protocol) activity
# Created: 2025-09-06

LOG_FILE="mcp_monitoring_$(date +%Y%m%d_%H%M%S).log"
ALERT_LOG="mcp_security_alerts.log"

echo "=== MCP Security Monitoring ==="
echo "Log file: $LOG_FILE"
echo "Alert log: $ALERT_LOG"
echo ""

# Initialize log files
cat > "$LOG_FILE" << EOF
MCP Security Monitoring Started: $(date)
========================================
EOF

cat > "$ALERT_LOG" << EOF
MCP Security Alerts Started: $(date)
====================================
EOF

log_message() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

security_alert() {
    echo "[$(date '+%H:%M:%S')] SECURITY ALERT: $1" | tee -a "$LOG_FILE" "$ALERT_LOG"
    echo -e "\033[0;31m[ALERT] $1\033[0m"
}

warning() {
    echo "[$(date '+%H:%M:%S')] WARNING: $1" | tee -a "$LOG_FILE" "$ALERT_LOG"
    echo -e "\033[1;33m[WARNING] $1\033[0m"
}

# Function to monitor MCP processes
monitor_mcp_processes() {
    log_message "Starting MCP process monitoring..."
    
    while true; do
        # Look for MCP-related processes
        MCP_PROCESSES=$(ps aux | grep -E "(mcp|modelcontextprotocol)" | grep -v grep)
        
        if [ -n "$MCP_PROCESSES" ]; then
            PROCESS_COUNT=$(echo "$MCP_PROCESSES" | wc -l)
            
            if [ $PROCESS_COUNT -gt 5 ]; then
                warning "High number of MCP processes: $PROCESS_COUNT"
            fi
            
            # Check for suspicious process names or arguments
            echo "$MCP_PROCESSES" | while read process; do
                if echo "$process" | grep -qE "(curl|wget|bash|sh|python.*-c)"; then
                    security_alert "Suspicious MCP process: $process"
                fi
            done
            
            # Monitor resource usage of MCP processes
            echo "$MCP_PROCESSES" | while read line; do
                PID=$(echo "$line" | awk '{print $2}')
                CPU=$(echo "$line" | awk '{print $3}')
                MEM=$(echo "$line" | awk '{print $4}')
                CMD=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf "%s ", $i; print ""}')
                
                # Alert on high resource usage
                if (( $(echo "$CPU > 50" | bc -l) )); then
                    warning "High CPU usage by MCP process PID $PID: ${CPU}%"
                fi
                
                if (( $(echo "$MEM > 10" | bc -l) )); then
                    warning "High memory usage by MCP process PID $PID: ${MEM}%"
                fi
                
                log_message "MCP Process: PID=$PID CPU=${CPU}% MEM=${MEM}% CMD=$CMD"
            done
        fi
        
        sleep 30
    done
}

# Function to monitor file access by MCP
monitor_mcp_file_access() {
    log_message "Starting MCP file access monitoring..."
    
    # Monitor sensitive directories
    SENSITIVE_DIRS=(
        "$HOME/.ssh"
        "$HOME/.aws" 
        "$HOME/.config"
        "/etc/passwd"
        "/etc/shadow"
        "$HOME/.bashrc"
        "$HOME/.bash_profile"
    )
    
    for dir in "${SENSITIVE_DIRS[@]}"; do
        if [ -e "$dir" ]; then
            inotifywait -m -r "$dir" --format '%w%f %e %T' --timefmt '%Y-%m-%d %H:%M:%S' 2>/dev/null | \
                while read path event time; do
                    # Check if access is from MCP process
                    ACCESSING_PIDS=$(lsof "$path" 2>/dev/null | awk 'NR>1 {print $2}' | head -5)
                    
                    for pid in $ACCESSING_PIDS; do
                        if [ -n "$pid" ]; then
                            PROCESS_CMD=$(ps -p $pid -o cmd --no-headers 2>/dev/null)
                            if echo "$PROCESS_CMD" | grep -qE "(mcp|modelcontextprotocol)"; then
                                security_alert "MCP process accessing sensitive file: $path (event: $event, time: $time)"
                            fi
                        fi
                    done
                done &
        fi
    done
}

# Function to monitor network activity
monitor_mcp_network() {
    log_message "Starting MCP network monitoring..."
    
    while true; do
        # Get MCP process PIDs
        MCP_PIDS=$(pgrep -f "mcp|modelcontextprotocol" 2>/dev/null)
        
        for pid in $MCP_PIDS; do
            # Check network connections for each MCP process
            CONNECTIONS=$(lsof -Pan -p $pid -i 2>/dev/null | grep ESTABLISHED)
            
            if [ -n "$CONNECTIONS" ]; then
                echo "$CONNECTIONS" | while read conn; do
                    REMOTE_ADDR=$(echo "$conn" | awk '{print $9}' | cut -d'>' -f2)
                    
                    # Alert on suspicious destinations
                    if echo "$REMOTE_ADDR" | grep -qE "(.*\.ru|.*\.cn|.*onion|tempfile|pastebin|discord)"; then
                        security_alert "Suspicious MCP network connection to: $REMOTE_ADDR from PID $pid"
                    fi
                    
                    log_message "MCP network connection: PID $pid -> $REMOTE_ADDR"
                done
            fi
        done
        
        sleep 60
    done
}

# Function to monitor command execution
monitor_mcp_commands() {
    log_message "Starting MCP command execution monitoring..."
    
    # Monitor bash history for dangerous commands
    tail -f ~/.bash_history 2>/dev/null | \
        grep -E "(rm -rf|sudo|curl.*bash|wget.*bash|chmod.*777|find.*-exec|dd if=)" | \
        while read dangerous_cmd; do
            # Check if command was executed by MCP process
            CURRENT_PPID=$(ps -o ppid= $$ 2>/dev/null)
            if [ -n "$CURRENT_PPID" ]; then
                PARENT_CMD=$(ps -p $CURRENT_PPID -o cmd --no-headers 2>/dev/null)
                if echo "$PARENT_CMD" | grep -qE "(mcp|modelcontextprotocol)"; then
                    security_alert "Dangerous command executed via MCP: $dangerous_cmd"
                fi
            fi
        done &
}

# Function to check for JSON-RPC MCP traffic
monitor_jsonrpc_traffic() {
    log_message "Starting JSON-RPC traffic monitoring..."
    
    # Monitor for JSON-RPC calls (requires root for tcpdump)
    if [ "$EUID" -eq 0 ]; then
        tcpdump -i any -A 2>/dev/null | \
            grep -E "(tools/call|tools/list|execute_command|read_file|write_file)" | \
            while read rpc_call; do
                if echo "$rpc_call" | grep -qE "(execute_command|delete_file|http_request)"; then
                    security_alert "High-risk MCP tool call detected: $rpc_call"
                else
                    log_message "MCP tool call: $rpc_call"
                fi
            done &
    else
        log_message "JSON-RPC monitoring requires root access (run with sudo for full monitoring)"
    fi
}

# Function to create monitoring dashboard
create_dashboard() {
    cat << 'EOF'
=== MCP Security Monitoring Dashboard ===

Commands to monitor MCP activity:

1. View real-time logs:
   tail -f LOG_FILE

2. View security alerts:
   tail -f ALERT_LOG

3. Check MCP processes:
   ps aux | grep -E "(mcp|modelcontextprotocol)"

4. Monitor network connections:
   lsof -i | grep mcp

5. Check file access:
   lsof | grep mcp

Press Ctrl+C to stop monitoring
EOF
}

# Cleanup function
cleanup() {
    log_message "Stopping MCP monitoring..."
    pkill -P $$  # Kill all child processes
    exit 0
}

# Set up signal handling
trap cleanup SIGINT SIGTERM

# Main monitoring loop
main() {
    create_dashboard | sed "s/LOG_FILE/$LOG_FILE/g; s/ALERT_LOG/$ALERT_LOG/g"
    
    echo ""
    log_message "Initializing MCP security monitoring..."
    
    # Start all monitoring functions in background
    monitor_mcp_processes &
    monitor_mcp_file_access &
    monitor_mcp_network &
    monitor_mcp_commands &
    monitor_jsonrpc_traffic &
    
    log_message "All monitoring processes started"
    
    # Keep main process alive and provide status updates
    while true; do
        sleep 300  # Update every 5 minutes
        
        ALERT_COUNT=$(wc -l < "$ALERT_LOG")
        PROCESS_COUNT=$(pgrep -f "mcp|modelcontextprotocol" | wc -l)
        
        log_message "Status: $ALERT_COUNT alerts, $PROCESS_COUNT MCP processes active"
        
        # Check for high alert rate
        RECENT_ALERTS=$(tail -10 "$ALERT_LOG" | grep "$(date '+%Y-%m-%d %H:')" | wc -l)
        if [ $RECENT_ALERTS -gt 5 ]; then
            security_alert "High alert rate detected: $RECENT_ALERTS alerts in last hour"
        fi
    done
}

# Check dependencies
if ! command -v inotifywait >/dev/null 2>&1; then
    echo "Warning: inotifywait not found. File monitoring may be limited."
    echo "Install with: sudo apt-get install inotify-tools"
fi

if ! command -v lsof >/dev/null 2>&1; then
    echo "Warning: lsof not found. Network monitoring may be limited."
    echo "Install with: sudo apt-get install lsof"
fi

# Start monitoring
main