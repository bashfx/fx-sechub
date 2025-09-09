#!/bin/bash
# claude_context_monitor.sh - Monitor Claude context pressure and predict degradation
# Generated: 2025-09-06
# Purpose: Calculate context pressure and predict 5-hour warning based on usage patterns

set -e

CLAUDE_DIR="$HOME/.claude"
PROJECTS_DIR="$CLAUDE_DIR/projects"
LOG_DIR="$HOME/.local/etc/agentic"
CONTEXT_LOG="$LOG_DIR/claude_context_analysis.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$CONTEXT_LOG"
}

analyze_daily_sessions() {
    local today=$(date '+%Y-%m-%d')
    log_message "=== CLAUDE CONTEXT ANALYSIS - $today ==="
    
    # Find today's sessions
    local sessions=$(find "$PROJECTS_DIR" -name "*.jsonl" -newermt "$today")
    local session_count=$(echo "$sessions" | wc -l)
    
    if [ -z "$sessions" ] || [ "$session_count" -eq 0 ]; then
        log_message "No sessions found for today"
        return 1
    fi
    
    log_message "Found $session_count active sessions today"
    
    # Calculate first session start time (daily baseline)
    local first_session=""
    local earliest_timestamp=""
    
    for session in $sessions; do
        if [ -s "$session" ]; then
            local session_start=$(head -1 "$session" | jq -r '.timestamp // empty' 2>/dev/null)
            if [ -n "$session_start" ] && [ "$session_start" != "null" ]; then
                if [ -z "$earliest_timestamp" ] || [[ "$session_start" < "$earliest_timestamp" ]]; then
                    earliest_timestamp="$session_start"
                    first_session="$session"
                fi
            fi
        fi
    done
    
    if [ -n "$earliest_timestamp" ]; then
        local readable_start=$(date -d "$earliest_timestamp" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || echo "$earliest_timestamp")
        log_message "Daily baseline start: $readable_start"
        
        # Calculate current duration since first session
        local start_epoch=$(date -d "$earliest_timestamp" +%s 2>/dev/null)
        local current_epoch=$(date +%s)
        local total_duration=$((current_epoch - start_epoch))
        local hours=$((total_duration / 3600))
        local minutes=$(((total_duration % 3600) / 60))
        
        log_message "Total active duration: ${hours}h ${minutes}m"
        
        # Predict 5-hour warning based on usage pressure
        predict_context_degradation "$sessions" "$total_duration"
    else
        log_message "ERROR: Could not determine session start times"
    fi
}

predict_context_degradation() {
    local sessions="$1"
    local total_duration="$2"
    
    log_message "--- Context Pressure Analysis ---"
    
    # Calculate usage metrics
    local total_cache_tokens=0
    local sonnet_usage=0
    local high_context_requests=0
    local concurrent_sessions=0
    
    # Count concurrent sessions (active in last hour)
    local recent_sessions=$(find "$PROJECTS_DIR" -name "*.jsonl" -newermt "1 hour ago" | wc -l)
    concurrent_sessions=$recent_sessions
    
    # Analyze each session for pressure indicators
    for session in $sessions; do
        if [ -s "$session" ]; then
            # Count Sonnet usage
            local session_sonnet=$(grep -c 'claude-sonnet' "$session" 2>/dev/null || echo 0)
            sonnet_usage=$((sonnet_usage + session_sonnet))
            
            # Sum cache read tokens
            local session_cache=$(grep '"cache_read_input_tokens"' "$session" 2>/dev/null | \
                jq '.message.usage.cache_read_input_tokens // 0' 2>/dev/null | \
                awk '{sum+=$1} END {print sum+0}' || echo 0)
            total_cache_tokens=$((total_cache_tokens + ${session_cache:-0}))
            
            # Count high context requests (>10K input tokens)
            local high_context=$(grep '"input_tokens"' "$session" 2>/dev/null | \
                jq '.message.usage.input_tokens // 0' 2>/dev/null | \
                awk '$1 > 10000 {count++} END {print count+0}' || echo 0)
            high_context_requests=$((high_context_requests + ${high_context:-0}))
        fi
    done
    
    log_message "Cache read tokens: $total_cache_tokens"
    log_message "Sonnet model usage: $sonnet_usage requests"
    log_message "High context requests: $high_context_requests"
    log_message "Concurrent sessions: $concurrent_sessions"
    
    # Calculate context pressure score (hypothesis)
    local time_factor=$((total_duration / 3600))  # Hours as base factor
    local cache_factor=$((total_cache_tokens / 10000))  # Every 10K cache tokens = +1 pressure
    local sonnet_factor=$((sonnet_usage / 10))  # Every 10 Sonnet requests = +1 pressure  
    local concurrent_factor=$((concurrent_sessions * 2))  # Each concurrent session = +2 pressure
    
    local context_pressure=$((time_factor + cache_factor + sonnet_factor + concurrent_factor))
    
    log_message "--- Context Pressure Calculation ---"
    log_message "Time factor: $time_factor"
    log_message "Cache factor: $cache_factor"  
    log_message "Sonnet factor: $sonnet_factor"
    log_message "Concurrent factor: $concurrent_factor"
    log_message "Total context pressure: $context_pressure"
    
    # Predict degradation warning (hypothesis thresholds)
    if [ "$context_pressure" -gt 15 ]; then
        echo -e "${RED}⚠️  HIGH RISK: Context degradation likely imminent${NC}"
        log_message "ALERT: High context pressure detected ($context_pressure > 15)"
    elif [ "$context_pressure" -gt 10 ]; then
        echo -e "${YELLOW}⚠️  MEDIUM RISK: Context efficiency may be degrading${NC}"
        log_message "WARNING: Moderate context pressure ($context_pressure > 10)"
    elif [ "$context_pressure" -gt 5 ]; then
        echo -e "${BLUE}ℹ️  LOW RISK: Normal usage patterns${NC}"
        log_message "INFO: Low context pressure ($context_pressure)"
    else
        echo -e "${GREEN}✅ OPTIMAL: Context efficiency preserved${NC}"
        log_message "GOOD: Minimal context pressure ($context_pressure)"
    fi
    
    # Prediction timeline
    if [ "$context_pressure" -gt 10 ]; then
        echo -e "${YELLOW}📅 Predicted context warning in: $((6 - time_factor)) hours (estimate)${NC}"
        log_message "PREDICTION: Context warning estimated in $((6 - time_factor)) hours"
    fi
}

analyze_agent_patterns() {
    log_message "--- Multi-Agent Usage Analysis ---"
    
    # Find agent-related sessions (based on directory patterns)
    local agent_sessions=$(find "$PROJECTS_DIR" -name "*.jsonl" -newermt "today" -path "*agent*" 2>/dev/null | wc -l)
    log_message "Agent-specific sessions today: $agent_sessions"
    
    # Look for rapid sequential agent usage
    local recent_agents=$(find "$PROJECTS_DIR" -name "*.jsonl" -newermt "30 minutes ago" | wc -l)
    if [ "$recent_agents" -gt 2 ]; then
        echo -e "${YELLOW}⚠️  Multiple agents active in last 30 minutes${NC}"
        log_message "WARNING: $recent_agents agents active recently (potential pressure trigger)"
    fi
}

# Main execution
main() {
    echo -e "${BLUE}=== Claude Context Pressure Monitor ===${NC}"
    echo "$(date '+%Y-%m-%d %H:%M:%S')"
    echo
    
    analyze_daily_sessions
    echo
    analyze_agent_patterns
    echo
    
    log_message "=== Analysis Complete ==="
    echo -e "${GREEN}📊 Full analysis logged to: $CONTEXT_LOG${NC}"
}

# Run if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi