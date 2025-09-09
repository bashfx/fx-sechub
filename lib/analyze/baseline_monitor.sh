#!/bin/bash
# AI API Baseline Monitoring Script
# Purpose: Establish normal usage patterns and detect anomalies
# Schedule: Run daily via cron to build baseline profiles

set -euo pipefail

# Configuration
BASELINE_DIR="$HOME/.local/etc/agentic"
BASELINE_LOG="$BASELINE_DIR/baseline_$(date +%Y%m%d).log"
ANOMALY_LOG="$BASELINE_DIR/anomaly_alerts.log"
ALERT_THRESHOLD_DAYS=7  # Need 7 days of data before anomaly detection

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Ensure directories exist
mkdir -p "$BASELINE_DIR"

log_baseline() {
    echo "[$(date '+%H:%M:%S')] BASELINE: $1" | tee -a "$BASELINE_LOG"
}

log_anomaly() {
    echo "[$(date '+%H:%M:%S')] ANOMALY: $1" | tee -a "$ANOMALY_LOG"
    echo -e "${RED}ANOMALY DETECTED: $1${NC}"
}

warning() {
    echo -e "${YELLOW}WARNING: $1${NC}" | tee -a "$ANOMALY_LOG"
}

# Get authentication tokens
get_openai_key() {
    if [ -f ~/.codex/auth.json ]; then
        jq -r '.OPENAI_API_KEY // empty' ~/.codex/auth.json 2>/dev/null || echo ""
    else
        echo ""
    fi
}

get_gemini_token() {
    if [ -f ~/.gemini/oauth_creds.json ]; then
        jq -r '.access_token // empty' ~/.gemini/oauth_creds.json 2>/dev/null || echo ""
    else
        echo ""
    fi
}

get_claude_token() {
    if [ -f ~/.claude/.credentials.json ]; then
        jq -r '.claudeAiOauth.accessToken // empty' ~/.claude/.credentials.json 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Collect system baseline metrics
collect_system_baseline() {
    log_baseline "=== System Baseline Metrics ==="
    
    # System resource usage
    local memory_usage=$(free | awk '/Mem/ {printf "%.0f", $3/$2 * 100}' 2>/dev/null || echo "0")
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}' 2>/dev/null || echo "0")
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//' 2>/dev/null || echo "0")
    
    log_baseline "Memory usage: ${memory_usage}%"
    log_baseline "CPU usage: ${cpu_usage}%"
    log_baseline "Disk usage: ${disk_usage}%"
    
    # Network connections to AI APIs
    local api_connections=$(netstat -tupln 2>/dev/null | grep -E "(openai|anthropic|googleapis)" | wc -l)
    log_baseline "Active API connections: $api_connections"
    
    # Running processes related to AI APIs
    local api_processes=$(ps aux | grep -E "(curl.*api\.|python.*openai|gemini|claude)" | grep -v grep | wc -l)
    log_baseline "AI API processes: $api_processes"
    
    # Time of day (detect off-hours usage)
    local current_hour=$(date +%H)
    log_baseline "Hour of day: $current_hour"
    
    # Day of week (detect weekend anomalies)
    local day_of_week=$(date +%u)  # 1=Monday, 7=Sunday
    log_baseline "Day of week: $day_of_week"
}

# OpenAI baseline collection
collect_openai_baseline() {
    log_baseline "=== OpenAI Baseline Collection ==="
    
    local api_key=$(get_openai_key)
    if [ -z "$api_key" ]; then
        log_baseline "No OpenAI API key found"
        return 0
    fi
    
    # Test free endpoint (models list)
    local models_response=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
        -H "Authorization: Bearer $api_key" \
        "https://api.openai.com/v1/models" 2>/dev/null || echo "ERROR")
    
    local http_code=$(echo "$models_response" | grep "HTTP_CODE:" | cut -d: -f2 2>/dev/null || echo "000")
    
    if [ "$http_code" == "200" ]; then
        local model_count=$(echo "$models_response" | sed '/HTTP_CODE:/d' | jq '.data | length' 2>/dev/null || echo "0")
        log_baseline "OpenAI models accessible: $model_count"
        log_baseline "OpenAI API status: OK"
    else
        log_baseline "OpenAI API status: ERROR ($http_code)"
        if [ "$http_code" == "401" ]; then
            log_anomaly "OpenAI authentication failure - possible token compromise"
        elif [ "$http_code" == "429" ]; then
            log_anomaly "OpenAI rate limited - possible quota abuse"
        fi
    fi
    
    # Check rate limit headers
    local rate_headers=$(curl -s -I -H "Authorization: Bearer $api_key" \
        "https://api.openai.com/v1/models" 2>/dev/null || echo "failed")
    
    if [ "$rate_headers" != "failed" ]; then
        local remaining_requests=$(echo "$rate_headers" | grep -i "x-ratelimit-remaining-requests" | cut -d: -f2 | tr -d ' \r' 2>/dev/null || echo "unknown")
        local limit_requests=$(echo "$rate_headers" | grep -i "x-ratelimit-limit-requests" | cut -d: -f2 | tr -d ' \r' 2>/dev/null || echo "unknown")
        
        if [ "$remaining_requests" != "unknown" ] && [ "$limit_requests" != "unknown" ]; then
            log_baseline "OpenAI rate limit: $remaining_requests/$limit_requests"
            
            # Check for concerning rate limit usage
            if [ "$remaining_requests" -lt 10 ] && [ "$limit_requests" -gt 50 ]; then
                warning "OpenAI rate limit nearly exhausted: $remaining_requests/$limit_requests"
            fi
        fi
    fi
}

# Gemini baseline collection
collect_gemini_baseline() {
    log_baseline "=== Gemini Baseline Collection ==="
    
    local access_token=$(get_gemini_token)
    if [ -z "$access_token" ]; then
        log_baseline "No Gemini access token found"
        return 0
    fi
    
    # Test free endpoint (models list)
    local models_response=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
        -H "Authorization: Bearer $access_token" \
        "https://generativelanguage.googleapis.com/v1beta/models" 2>/dev/null || echo "ERROR")
    
    local http_code=$(echo "$models_response" | grep "HTTP_CODE:" | cut -d: -f2 2>/dev/null || echo "000")
    
    if [ "$http_code" == "200" ]; then
        local model_count=$(echo "$models_response" | sed '/HTTP_CODE:/d' | jq '.models | length' 2>/dev/null || echo "0")
        log_baseline "Gemini models accessible: $model_count"
        log_baseline "Gemini quota status: OK"
    else
        log_baseline "Gemini quota status: ERROR ($http_code)"
        if [ "$http_code" == "401" ]; then
            log_anomaly "Gemini authentication failure - token may be compromised"
        elif [ "$http_code" == "429" ]; then
            log_anomaly "Gemini quota exceeded - possible abuse or daily limit reached"
        fi
    fi
    
    # Check token expiry
    if [ -f ~/.gemini/oauth_creds.json ]; then
        local expiry_date=$(jq -r '.expiry_date // 0' ~/.gemini/oauth_creds.json 2>/dev/null || echo "0")
        local current_time=$(date +%s)
        
        if [ "$expiry_date" -gt 9999999999 ]; then
            expiry_date=$((expiry_date / 1000))
        fi
        
        if [ "$expiry_date" -gt 0 ]; then
            local hours_until_expiry=$(( (expiry_date - current_time) / 3600 ))
            log_baseline "Gemini token expires in: $hours_until_expiry hours"
            
            if [ "$hours_until_expiry" -lt 24 ]; then
                warning "Gemini token expires soon: $hours_until_expiry hours"
            fi
        fi
    fi
}

# Claude baseline collection  
collect_claude_baseline() {
    log_baseline "=== Claude Baseline Collection ==="
    
    local access_token=$(get_claude_token)
    if [ -z "$access_token" ]; then
        log_baseline "No Claude access token found"
        return 0
    fi
    
    # Test API access (Claude has fewer free endpoints)
    local test_response=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
        -H "Authorization: Bearer $access_token" \
        -H "anthropic-version: 2023-06-01" \
        "https://api.anthropic.com/v1/messages" \
        -d '{}' 2>/dev/null || echo "ERROR")
    
    local http_code=$(echo "$test_response" | grep "HTTP_CODE:" | cut -d: -f2 2>/dev/null || echo "000")
    
    # We expect 400 for empty request, not 401/403/500
    if [ "$http_code" == "400" ]; then
        log_baseline "Claude API status: OK (accessible)"
    elif [ "$http_code" == "401" ]; then
        log_baseline "Claude API status: AUTH_ERROR"
        log_anomaly "Claude authentication failure - token may be compromised"
    elif [ "$http_code" == "429" ]; then
        log_baseline "Claude API status: RATE_LIMITED"
        log_anomaly "Claude rate limited - possible quota abuse"
    else
        log_baseline "Claude API status: ERROR ($http_code)"
    fi
    
    # Check subscription info
    if [ -f ~/.claude/.credentials.json ]; then
        local subscription=$(jq -r '.claudeAiOauth.subscriptionType // "unknown"' ~/.claude/.credentials.json 2>/dev/null)
        local expires_at=$(jq -r '.claudeAiOauth.expiresAt // 0' ~/.claude/.credentials.json 2>/dev/null)
        
        log_baseline "Claude subscription: $subscription"
        
        if [ "$expires_at" -gt 0 ]; then
            local current_time=$(date +%s)
            if [ "$expires_at" -gt 9999999999 ]; then
                expires_at=$((expires_at / 1000))
            fi
            
            local hours_until_expiry=$(( (expires_at - current_time) / 3600 ))
            log_baseline "Claude token expires in: $hours_until_expiry hours"
            
            if [ "$hours_until_expiry" -lt 24 ]; then
                warning "Claude token expires soon: $hours_until_expiry hours"
            fi
        fi
    fi
}

# Analyze historical data for anomalies
detect_anomalies() {
    log_baseline "=== Anomaly Detection Analysis ==="
    
    # Check if we have enough historical data
    local baseline_files=$(find "$BASELINE_DIR" -name "baseline_*.log" -mtime -$ALERT_THRESHOLD_DAYS | wc -l)
    
    if [ "$baseline_files" -lt "$ALERT_THRESHOLD_DAYS" ]; then
        log_baseline "Insufficient historical data ($baseline_files days) - building baseline"
        return 0
    fi
    
    # Analyze API process patterns
    local current_api_processes=$(ps aux | grep -E "(curl.*api\.|python.*openai|gemini|claude)" | grep -v grep | wc -l)
    local avg_api_processes=$(grep "AI API processes:" "$BASELINE_DIR"/baseline_*.log | tail -7 | awk '{sum+=$4} END {print int(sum/NR)}' 2>/dev/null || echo "0")
    
    if [ "$current_api_processes" -gt $((avg_api_processes * 3)) ]; then
        log_anomaly "Unusual number of API processes: $current_api_processes (avg: $avg_api_processes)"
    fi
    
    # Analyze time-based patterns
    local current_hour=$(date +%H)
    if [ "$current_hour" -ge 22 ] || [ "$current_hour" -le 6 ]; then
        if [ "$current_api_processes" -gt 0 ]; then
            log_anomaly "API activity detected during off-hours (${current_hour}:00)"
        fi
    fi
    
    # Analyze memory usage patterns
    local current_memory=$(free | awk '/Mem/ {printf "%.0f", $3/$2 * 100}' 2>/dev/null || echo "0")
    local avg_memory=$(grep "Memory usage:" "$BASELINE_DIR"/baseline_*.log | tail -7 | awk -F': ' '{gsub(/%/, "", $2); sum+=$2} END {print int(sum/NR)}' 2>/dev/null || echo "0")
    
    if [ "$current_memory" -gt $((avg_memory + 20)) ]; then
        warning "Memory usage spike: $current_memory% (avg: $avg_memory%)"
    fi
    
    # Check for API connection anomalies
    local current_connections=$(netstat -tupln 2>/dev/null | grep -E "(openai|anthropic|googleapis)" | wc -l)
    local avg_connections=$(grep "Active API connections:" "$BASELINE_DIR"/baseline_*.log | tail -7 | awk '{sum+=$4} END {print int(sum/NR)}' 2>/dev/null || echo "0")
    
    if [ "$current_connections" -gt $((avg_connections * 5)) ]; then
        log_anomaly "Unusual API connection count: $current_connections (avg: $avg_connections)"
    fi
}

# Generate daily summary report
generate_summary() {
    local timestamp=$(date)
    local summary_file="$BASELINE_DIR/daily_summary_$(date +%Y%m%d).txt"
    
    cat > "$summary_file" << EOF
AI API Baseline Monitoring Summary
Generated: $timestamp

=== DAILY METRICS ===
EOF
    
    # Extract key metrics from today's log
    if [ -f "$BASELINE_LOG" ]; then
        echo "" >> "$summary_file"
        echo "System Metrics:" >> "$summary_file"
        grep -E "(Memory usage|CPU usage|API processes)" "$BASELINE_LOG" | tail -3 >> "$summary_file"
        
        echo "" >> "$summary_file"
        echo "API Status:" >> "$summary_file"
        grep -E "(API status|quota status|rate limit)" "$BASELINE_LOG" >> "$summary_file"
    fi
    
    # Check for any anomalies today
    if [ -f "$ANOMALY_LOG" ]; then
        local today_anomalies=$(grep "$(date +%Y-%m-%d)" "$ANOMALY_LOG" | wc -l)
        echo "" >> "$summary_file"
        echo "Anomalies Detected Today: $today_anomalies" >> "$summary_file"
        
        if [ "$today_anomalies" -gt 0 ]; then
            echo "" >> "$summary_file"
            echo "Anomaly Details:" >> "$summary_file"
            grep "$(date +%Y-%m-%d)" "$ANOMALY_LOG" >> "$summary_file"
        fi
    fi
    
    echo -e "\n${BLUE}Daily summary saved: $summary_file${NC}"
}

# Main execution
main() {
    echo "AI API Baseline Monitor - $(date)"
    echo "======================================"
    
    collect_system_baseline
    collect_openai_baseline
    collect_gemini_baseline
    collect_claude_baseline
    detect_anomalies
    generate_summary
    
    # Check if any anomalies were detected
    if [ -f "$ANOMALY_LOG" ] && grep -q "$(date +%Y-%m-%d)" "$ANOMALY_LOG" 2>/dev/null; then
        echo -e "\n${RED}⚠️  ANOMALIES DETECTED TODAY${NC}"
        echo "Review: $ANOMALY_LOG"
        return 1
    else
        echo -e "\n${GREEN}✓ No anomalies detected${NC}"
        return 0
    fi
}

main "$@"