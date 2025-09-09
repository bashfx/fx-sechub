#!/bin/bash
# claude_usage_monitor_v2.sh - Properly Fixed Version with JSON Timestamp Analysis
# Mission: MISSION_01_CLAUDE_USAGE_DETECTION - CORRECTED IMPLEMENTATION
# Commander: Edgar (EDGAROS) - Vigilant Sentinel

set -euo pipefail

# Tool metadata
TOOL_NAME="Claude Usage Monitor v2.0"
TOOL_VERSION="2.0.0-FIXED"
TOOL_MISSION="MISSION_01_CLAUDE_USAGE_DETECTION"

# Core directories
CLAUDE_DIR="$HOME/.claude"
PROJECTS_DIR="$CLAUDE_DIR/projects"
CONFIG_DIR="$HOME/.local/etc/agentic"

# Boxy orchestrator - handles graceful fallback
use_boxy() {
    if command -v boxy >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Enhanced output with boxy integration and fallback
print_header() {
    local title="$1"
    local theme="${2:-info}"
    
    if use_boxy; then
        echo "$title" | boxy --theme "$theme" --header "🛡️ $TOOL_NAME"
    else
        echo "=============================================="
        echo "🛡️ $TOOL_NAME"
        echo "$title"
        echo "=============================================="
    fi
}

print_section() {
    local content="$1"
    local theme="${2:-info}"
    local title="${3:-}"
    
    if use_boxy; then
        if [ -n "$title" ]; then
            echo -e "$content" | boxy --theme "$theme" --title "$title" --width max
        else
            echo -e "$content" | boxy --theme "$theme" --width max
        fi
    else
        if [ -n "$title" ]; then
            echo "--- $title ---"
        fi
        echo -e "$content"
        echo
    fi
}

# CORRECT IMPLEMENTATION: JSON timestamp-based session discovery
find_sessions_with_json_timestamps() {
    local hours_back="${1:-1}"
    local today=$(date -u +"%Y-%m-%d")
    local cutoff_epoch=$(date -d "$hours_back hours ago" +%s)
    
    # Step 1: OPTIMIZATION - Use grep to pre-filter files containing today's date
    local candidate_files=$(find "$PROJECTS_DIR" -name "*.jsonl" -type f \
        -exec grep -l "$today" {} \; 2>/dev/null)
    
    if [[ -z "$candidate_files" ]]; then
        return 0
    fi
    
    # Step 2: Parse JSON timestamps from candidates to find genuine recent activity  
    local active_sessions=""
    while IFS= read -r session_file; do
        if [[ -n "$session_file" ]] && [[ -f "$session_file" ]]; then
            # Get the most recent timestamp from this session (check last few entries)
            local latest_timestamp=$(timeout 5s tail -10 "$session_file" | \
                                   grep '"timestamp":' | tail -1 | \
                                   sed 's/.*"timestamp":"\([^"]*\)".*/\1/' 2>/dev/null || echo "")
            
            if [[ -n "$latest_timestamp" ]]; then
                # Convert JSON timestamp to epoch for comparison
                local session_epoch=$(date -d "$latest_timestamp" +%s 2>/dev/null || echo 0)
                
                if [[ "$session_epoch" -gt "$cutoff_epoch" ]]; then
                    active_sessions+="$session_file|$latest_timestamp|$session_epoch\n"
                fi
            fi
        fi
    done <<< "$candidate_files"
    
    echo -e "$active_sessions"
}

# Session status analysis with CORRECT JSON timestamp parsing
analyze_session_status() {
    print_header "Current Session Status (JSON-Based)" "info"
    
    # Get sessions active in last hour using JSON timestamps
    local active_sessions_data=$(find_sessions_with_json_timestamps 1)
    local active_count=0
    if [[ -n "$active_sessions_data" ]]; then
        active_count=$(echo -e "$active_sessions_data" | grep -c "|" 2>/dev/null || echo 0)
    fi
    
    # Get today's sessions using JSON timestamps  
    local today_sessions_data=$(find_sessions_with_json_timestamps 24)
    local today_count=0
    if [[ -n "$today_sessions_data" ]]; then
        today_count=$(echo -e "$today_sessions_data" | grep -c "|" 2>/dev/null || echo 0)
    fi
    
    # Build status report
    local status_report=""
    status_report+="Active Sessions (last hour): $active_count\n"
    status_report+="Today's Sessions: $today_count\n\n"
    
    if [[ "$active_count" -gt 0 ]]; then
        status_report+="🔄 Currently Active Sessions:\n"
        
        while IFS='|' read -r session_file timestamp epoch; do
            if [[ -n "$session_file" ]]; then
                local project_dir=$(dirname "$session_file")
                local project_name=$(basename "$project_dir" | sed 's/-home-xnull-repos-/-/' | sed 's/-/\//g')
                local session_id=$(basename "$session_file" .jsonl)
                local current_epoch=$(date +%s)
                local minutes_ago=$(( (current_epoch - epoch) / 60 ))
                
                status_report+="• $project_name - ${session_id:0:8} (${minutes_ago}m ago)\n"
            fi
        done <<< "$active_sessions_data"
    fi
    
    print_section "$status_report" "info"
}

# Usage pattern analysis with JSON timestamp reconstruction
analyze_usage_patterns() {
    print_header "Usage Pattern Analysis (JSON-Based)" "info"
    
    local today_sessions_data=$(find_sessions_with_json_timestamps 24)
    
    if [[ -z "$today_sessions_data" ]]; then
        print_section "No sessions found for today" "warning"
        return 0
    fi
    
    local total_messages=0
    local total_sessions=0
    local session_details=""
    
    # Analyze each session that had activity today
    while IFS='|' read -r session_file timestamp epoch; do
        if [[ -n "$session_file" ]] && [[ -f "$session_file" ]]; then
            total_sessions=$((total_sessions + 1))
            
            # Count messages and analyze session
            local session_messages=$(wc -l < "$session_file" 2>/dev/null || echo 0)
            total_messages=$((total_messages + session_messages))
            
            local project_name=$(basename "$(dirname "$session_file")" | sed 's/-home-xnull-repos-/-/' | sed 's/-/\//g')
            local session_id=$(basename "$session_file" .jsonl)
            local file_size=$(du -h "$session_file" 2>/dev/null | cut -f1)
            
            session_details+="• $project_name - ${session_id:0:8} ($session_messages messages, $file_size)\n"
        fi
    done <<< "$today_sessions_data"
    
    # Build analysis report
    local analysis_report=""
    analysis_report+="📊 Today's Usage Summary (JSON-Based Analysis):\n"
    analysis_report+="• Active Sessions Today: $total_sessions\n"
    analysis_report+="• Total Messages: $total_messages\n"
    analysis_report+="• Average Messages/Session: $((total_messages / (total_sessions > 0 ? total_sessions : 1)))\n\n"
    analysis_report+="📋 Session Details:\n"
    analysis_report+="$session_details"
    
    print_section "$analysis_report" "info"
}

# Main dashboard
show_dashboard() {
    analyze_session_status
    echo
    analyze_usage_patterns
    echo
    
    # System status
    local total_files=$(find "$PROJECTS_DIR" -name "*.jsonl" 2>/dev/null | wc -l)
    local today_with_activity=$(find_sessions_with_json_timestamps 24 | grep -c "|" 2>/dev/null || echo 0)
    
    local system_status=""
    system_status+="📈 Monitoring Status (CORRECTED v2.0):\n"
    system_status+="• Analysis Method: JSON timestamp parsing (not file system times)\n"
    system_status+="• Total Session Files: $total_files\n"
    system_status+="• Files with Today's Activity: $today_with_activity\n"
    system_status+="• Data Source: $PROJECTS_DIR\n"
    
    print_section "$system_status" "success" "⚙️ System Status"
}

# Command help
show_help() {
    print_header "Claude Usage Monitor v2.0 - CORRECTED Implementation" "info"
    
    local help_text=""
    help_text+="🎯 CORRECTED FEATURES:\n"
    help_text+="  dashboard        Complete usage analysis with JSON timestamp parsing\n"
    help_text+="  status          Current session status using actual JSON timestamps\n"
    help_text+="  patterns        Usage patterns based on JSON content analysis\n\n"
    
    help_text+="🔧 KEY IMPROVEMENTS:\n"
    help_text+="• Uses grep pre-filtering for performance optimization\n"
    help_text+="• Analyzes JSON timestamps instead of file modification times\n"
    help_text+="• Properly reconstructs session activity timing\n"
    help_text+="• Shows genuine session usage vs. file system metadata\n\n"
    
    help_text+="📋 Mission: $TOOL_MISSION\n"
    help_text+="🛡️ Version: CORRECTED Implementation v2.0\n"
    help_text+="⚡ Optimization: grep + JSON timestamp analysis\n"
    
    print_section "$help_text" "info"
}

# Main command dispatcher
main() {
    # Check if Claude directory exists
    if [ ! -d "$PROJECTS_DIR" ]; then
        print_section "Claude projects directory not found: $PROJECTS_DIR\nPlease ensure Claude CLI is installed and has been used at least once." "error"
        exit 1
    fi
    
    # Command dispatch
    case "${1:-dashboard}" in
        "status")
            analyze_session_status
            ;;
        "dashboard")
            show_dashboard
            ;;
        "patterns")
            analyze_usage_patterns
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            print_section "Unknown command: $1\nUse 'help' for command reference." "error"
            show_help
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"