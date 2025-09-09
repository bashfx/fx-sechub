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
SNAPSHOT_DIR="$HOME/.local/share/agentic/ccuse"
COOL_MODE="${COOL_MODE:-1}";

# Boxy orchestrator - handles graceful fallback
use_boxy() {
	if command -v boxy >/dev/null 2>&1; then
			return 0
	else
			return 1
	fi
}

use_jynx() {
	if command -v jynx >/dev/null 2>&1; then
			return 0
	else
			return 1
	fi
}

__current_time(){
	echo "$(date +'%_I:%M %p')";
}

__current_date(){
	echo "$(date +"%Y-%m-%d")";
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

stdprint(){
	if [ "$COOL_MODE" -ne 0 ] || [ -z "${2:-}" ]; then
		printf "%b" "${1}\n" 1>&2;
	else
		if [ "$COOL_MODE" -eq 0 ]; then
				printx "$@";
		fi;
	fi
}

__task_count(){	
	local num  this=0; session_file="$1"
	this=$(grep -o '"name":"Task"' "$session_file" 2>/dev/null | wc -l || echo "0");
	num=$(printf "%d" "$this" 2>/dev/null || echo 0) #cast string to num
	echo $num;
}

__sub_agent_types(){
	local this="" session_file="$1"
	this=$(grep -o '"subagent_type":"[^"]*"' "$session_file" 2>/dev/null | \
										sed 's/"subagent_type":"//g' | sed 's/"//g' | sort | uniq -c | \
										awk '{print $2 "(" $1 ")"}' | paste -sd "," - || echo "none")
	echo "$this";
}

__total_messages(){
	local num this session_file="$1"
	this=$(grep -c '"type":"' "$session_file" 2>/dev/null || echo "0");
	num=$(printf "%d" "$this" 2>/dev/null || echo 0); #cast string to num
	echo $num;
}

# CORRECT IMPLEMENTATION: JSON timestamp-based session discovery
# Function to analyze subagent usage in a session
analyze_subagent_usage() {
    local session_file="$1"
    
    # Count Task tool invocations (indicating subagent launches)
    local task_count
    task_count=$(__task_count "$session_file")
    
    # Extract subagent types used
    local subagent_types=""
    if [ "$task_count" -gt 0 ]; then
      subagent_types=$(__sub_agent_types "$session_file");
    else
      subagent_types="none";
    fi
    
    # Count total messages in session  
    local total_messages
    total_messages=$(__total_messages "$session_file")
    
    # Estimate subagent vs main session messages
    local estimated_subagent_messages=0
    if [ "$task_count" -gt 0 ]; then
        # Conservative estimate: Each Task invocation generates ~15-30 messages on average
        estimated_subagent_messages=$((task_count * 20))
    fi
    
    local estimated_main_messages=$((total_messages - estimated_subagent_messages))
    if [ $estimated_main_messages -lt 0 ]; then
        estimated_main_messages=$total_messages
        estimated_subagent_messages=0
    fi
    
    echo "$task_count|$subagent_types|$estimated_main_messages|$estimated_subagent_messages|$total_messages"
}



find_sessions_with_json_timestamps() {
    local hours_back="${1:-1}"
    local today=$(__current_date)  # Use local time, not UTC
    local cutoff_epoch=$(date -d "$hours_back hours ago" +%s)

		stdprint "Today is $today $(__current_time)x"
    
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
    
    # Calculate comprehensive metrics for dashboard ceremony
    local today_sessions_data=$(find_sessions_with_json_timestamps 24)
    local total_messages_today=0
    local session_count=0
    local unique_projects=()
    local total_session_duration_minutes=0
    local earliest_session_time=""
    local latest_session_time=""
    local total_file_size_bytes=0
    
    # Subagent analysis tracking
    local total_task_invocations=0
    local total_estimated_subagent_messages=0
    local total_estimated_main_messages=0
    local unique_subagent_types=()
    
    # Process today's sessions for metrics
    while IFS='|' read -r session_file timestamp epoch; do
        if [[ -n "$session_file" ]] && [[ -f "$session_file" ]]; then
            session_count=$((session_count + 1))
            
            # Message count
            local session_messages=$(wc -l < "$session_file" 2>/dev/null || echo 0)
            total_messages_today=$((total_messages_today + session_messages))
            
            # Subagent analysis for this session
            local subagent_analysis=$(analyze_subagent_usage "$session_file")
            IFS='|' read -r task_count subagent_types main_msgs subagent_msgs total_msgs <<< "$subagent_analysis"
            
            total_task_invocations=$((total_task_invocations + task_count))
            total_estimated_subagent_messages=$((total_estimated_subagent_messages + subagent_msgs))
            total_estimated_main_messages=$((total_estimated_main_messages + main_msgs))
            
            # Track unique subagent types
            if [[ "$subagent_types" != "none" ]]; then
                IFS=',' read -ra AGENT_TYPES <<< "$subagent_types"
                for agent_type in "${AGENT_TYPES[@]}"; do
                    # Extract just the agent name (before parentheses)
                    local agent_name=$(echo "$agent_type" | sed 's/(.*//')
                    if [[ ! " ${unique_subagent_types[@]} " =~ " ${agent_name} " ]]; then
                        unique_subagent_types+=("$agent_name")
                    fi
                done
            fi
            
            # File size
            local file_size_bytes=$(stat -f%z "$session_file" 2>/dev/null || stat -c%s "$session_file" 2>/dev/null || echo 0)
            total_file_size_bytes=$((total_file_size_bytes + file_size_bytes))
            
            # Project tracking
            local project_name=$(basename "$(dirname "$session_file")" | sed 's/-home-xnull-repos-/-/' | sed 's/-/\//g')
            if [[ ! " ${unique_projects[@]} " =~ " ${project_name} " ]]; then
                unique_projects+=("$project_name")
            fi
            
            # Session timing
            if [[ -z "$earliest_session_time" ]] || [[ $epoch -lt $(date -d "$earliest_session_time" +%s 2>/dev/null || echo $epoch) ]]; then
                earliest_session_time="$timestamp"
            fi
            if [[ -z "$latest_session_time" ]] || [[ $epoch -gt $(date -d "$latest_session_time" +%s 2>/dev/null || echo $epoch) ]]; then
                latest_session_time="$timestamp"
            fi
        fi
    done <<< "$today_sessions_data"
    
    # Calculate estimated active session time (more realistic than time span)
    # Estimate: each message represents ~30 seconds of active conversation
    local estimated_active_minutes=$((total_messages_today / 2))  # 2 messages per minute avg
    
    # Convert to hours and minutes
    local hours=$((estimated_active_minutes / 60))
    local minutes=$((estimated_active_minutes % 60))
    local duration_display="${hours}h ${minutes}m (estimated active time)"
    
    # Also calculate time span for reference
    local time_span_minutes=0
    if [[ -n "$earliest_session_time" ]] && [[ -n "$latest_session_time" ]]; then
        local earliest_epoch=$(date -d "$earliest_session_time" +%s 2>/dev/null || echo 0)
        local latest_epoch=$(date -d "$latest_session_time" +%s 2>/dev/null || echo 0)
        time_span_minutes=$(( (latest_epoch - earliest_epoch) / 60 ))
    fi
    local span_hours=$((time_span_minutes / 60))
    local span_minutes=$((time_span_minutes % 60))
    local span_display="${span_hours}h ${span_minutes}m (time span)"
    
    # Estimate token usage
    local estimated_tokens=$((total_file_size_bytes / 4))
    
    # Create subagent summary
    local subagent_list=""
    if [ ${#unique_subagent_types[@]} -gt 0 ]; then
        subagent_list=$(IFS=', '; echo "${unique_subagent_types[*]}")
    else
        subagent_list="none"
    fi
    
    # Dashboard summary ceremony
    local dashboard_ceremony=""
    dashboard_ceremony+="📊 TODAY'S USAGE SUMMARY:\n"
    dashboard_ceremony+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    dashboard_ceremony+="🔢 Total Messages: $total_messages_today across $session_count sessions\n"
    dashboard_ceremony+="⏱️  Active Duration: $duration_display\n"
    dashboard_ceremony+="🗂️  Project Contexts: ${#unique_projects[@]} unique projects\n"
    dashboard_ceremony+="💾 Estimated Tokens: ~$estimated_tokens total\n"
    dashboard_ceremony+="📈 Average: $((total_messages_today / (session_count > 0 ? session_count : 1))) messages/session\n"
    dashboard_ceremony+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    dashboard_ceremony+="🤖 SUBAGENT ANALYSIS:\n"
    dashboard_ceremony+="• Task Invocations: $total_task_invocations subagent launches\n"
    dashboard_ceremony+="• Agent Types Used: $subagent_list\n"
    dashboard_ceremony+="• Estimated Main Messages: ~$total_estimated_main_messages ($(( total_estimated_main_messages * 100 / (total_messages_today > 0 ? total_messages_today : 1) ))%)\n"
    dashboard_ceremony+="• Estimated Subagent Messages: ~$total_estimated_subagent_messages ($(( total_estimated_subagent_messages * 100 / (total_messages_today > 0 ? total_messages_today : 1) ))%)\n"
    dashboard_ceremony+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    print_section "$dashboard_ceremony" "info" "📋 Usage Overview"
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

# Snapshot system for historical analysis and limit debugging
ensure_snapshot_dir() {
    mkdir -p "$SNAPSHOT_DIR"
}

# Create comprehensive usage snapshot in JSON format
create_usage_snapshot() {
    local snapshot_type="${1:-manual}"
    local trigger_reason="${2:-user_requested}"
    
    ensure_snapshot_dir
    
    local timestamp=$(date +"%Y-%m-%dT%H:%M:%S")  # Local time, not UTC
    local date_key=$(date +"%Y%m%d")
    local time_key=$(date +"%H%M%S")
    local snapshot_file="$SNAPSHOT_DIR/snapshot_${date_key}_${time_key}_${snapshot_type}.json"
    
    # Collect comprehensive usage data
    local active_sessions_data=$(find_sessions_with_json_timestamps 1)
    local today_sessions_data=$(find_sessions_with_json_timestamps 24)
    local total_files=$(find "$PROJECTS_DIR" -name "*.jsonl" 2>/dev/null | wc -l)
    
    # Count sessions and messages
    local active_count=0
    local today_count=0
    local total_messages_today=0
    
    if [[ -n "$active_sessions_data" ]]; then
        active_count=$(echo -e "$active_sessions_data" | grep -c "|" 2>/dev/null || echo 0)
    fi
    
    if [[ -n "$today_sessions_data" ]]; then
        today_count=$(echo -e "$today_sessions_data" | grep -c "|" 2>/dev/null || echo 0)
        
        # Count total messages for today
        while IFS='|' read -r session_file timestamp epoch; do
            if [[ -n "$session_file" ]] && [[ -f "$session_file" ]]; then
                local session_messages=$(wc -l < "$session_file" 2>/dev/null || echo 0)
                total_messages_today=$((total_messages_today + session_messages))
            fi
        done <<< "$today_sessions_data"
    fi
    
    # Calculate average messages per session safely
    local avg_messages_per_session
    if [[ $today_count -gt 0 ]]; then
        avg_messages_per_session=$((total_messages_today / today_count))
    else
        avg_messages_per_session=0
    fi
    
    # Build comprehensive JSON snapshot
    cat > "$snapshot_file" << EOF
{
  "snapshot_metadata": {
    "timestamp": "$timestamp",
    "snapshot_type": "$snapshot_type",
    "trigger_reason": "$trigger_reason",
    "version": "$TOOL_VERSION"
  },
  "usage_summary": {
    "active_sessions_1h": $active_count,
    "active_sessions_24h": $today_count,
    "total_messages_today": $total_messages_today,
    "total_session_files": $total_files,
    "avg_messages_per_session": $avg_messages_per_session
  },
  "session_details": [
EOF
    
    # Add session details to JSON
    local first_session=true
    while IFS='|' read -r session_file timestamp epoch; do
        if [[ -n "$session_file" ]] && [[ -f "$session_file" ]]; then
            if [ "$first_session" = false ]; then
                echo "    ," >> "$snapshot_file"
            fi
            first_session=false
            
            local project_name=$(basename "$(dirname "$session_file")" | sed 's/-home-xnull-repos-/-/' | sed 's/-/\//g')
            local session_id=$(basename "$session_file" .jsonl)
            local session_messages=$(wc -l < "$session_file" 2>/dev/null || echo 0)
            local file_size_bytes=$(stat -f%z "$session_file" 2>/dev/null || stat -c%s "$session_file" 2>/dev/null || echo 0)
            
            cat >> "$snapshot_file" << EOF
    {
      "session_file": "$session_file",
      "project_name": "$project_name",
      "session_id": "$session_id",
      "last_activity": "$timestamp",
      "message_count": $session_messages,
      "file_size_bytes": $file_size_bytes
    }
EOF
        fi
    done <<< "$today_sessions_data"
    
    # Close JSON structure
    cat >> "$snapshot_file" << EOF

  ],
  "system_info": {
    "claude_dir": "$CLAUDE_DIR",
    "projects_dir": "$PROJECTS_DIR",
    "snapshot_dir": "$SNAPSHOT_DIR"
  }
}
EOF
    
    echo "$snapshot_file"
}

# Create snapshot specifically for token/time limit analysis
create_limit_snapshot() {
    local limit_type="${1:-unknown}"
    local current_usage="${2:-unknown}"
    local limit_value="${3:-unknown}"
    
    local snapshot_file=$(create_usage_snapshot "limit" "${limit_type}_at_${current_usage}_of_${limit_value}")
    
    # Add limit-specific analysis to a companion file with comprehensive metrics
    local analysis_file="${snapshot_file%.json}_analysis.txt"
    
    # Calculate comprehensive usage metrics
    local today_sessions_data=$(find_sessions_with_json_timestamps 24)
    local total_messages_today=0
    local total_file_size_bytes=0
    local session_count=0
    local unique_projects=()
    local total_session_duration_minutes=0
    local earliest_session_time=""
    local latest_session_time=""
    
    # Process today's sessions for metrics
    while IFS='|' read -r session_file timestamp epoch; do
        if [[ -n "$session_file" ]] && [[ -f "$session_file" ]]; then
            session_count=$((session_count + 1))
            
            # Message count
            local session_messages=$(wc -l < "$session_file" 2>/dev/null || echo 0)
            total_messages_today=$((total_messages_today + session_messages))
            
            # File size
            local file_size_bytes=$(stat -f%z "$session_file" 2>/dev/null || stat -c%s "$session_file" 2>/dev/null || echo 0)
            total_file_size_bytes=$((total_file_size_bytes + file_size_bytes))
            
            # Project tracking
            local project_name=$(basename "$(dirname "$session_file")" | sed 's/-home-xnull-repos-/-/' | sed 's/-/\//g')
            if [[ ! " ${unique_projects[@]} " =~ " ${project_name} " ]]; then
                unique_projects+=("$project_name")
            fi
            
            # Session timing
            if [[ -z "$earliest_session_time" ]] || [[ $epoch -lt $(date -d "$earliest_session_time" +%s 2>/dev/null || echo $epoch) ]]; then
                earliest_session_time="$timestamp"
            fi
            if [[ -z "$latest_session_time" ]] || [[ $epoch -gt $(date -d "$latest_session_time" +%s 2>/dev/null || echo $epoch) ]]; then
                latest_session_time="$timestamp"
            fi
        fi
    done <<< "$today_sessions_data"
    
    # Calculate session duration
    if [[ -n "$earliest_session_time" ]] && [[ -n "$latest_session_time" ]]; then
        local earliest_epoch=$(date -d "$earliest_session_time" +%s 2>/dev/null || echo 0)
        local latest_epoch=$(date -d "$latest_session_time" +%s 2>/dev/null || echo 0)
        total_session_duration_minutes=$(( (latest_epoch - earliest_epoch) / 60 ))
    fi
    
    # Estimate token usage (rough calculation: ~4 chars per token average)
    local estimated_tokens=$((total_file_size_bytes / 4))
    
    cat > "$analysis_file" << EOF
LIMIT TRIGGER ANALYSIS
=====================

Trigger: $limit_type limit reached
Current Usage: $current_usage
Limit Value: $limit_value
Timestamp: $(date +"%Y-%m-%dT%H:%M:%S %Z") (Local Time)

CALCULATED USAGE SUMMARY (Today):
=================================
• Total Messages: $total_messages_today
• Total Sessions: $session_count
• Unique Projects: ${#unique_projects[@]}
• Session Duration: $total_session_duration_minutes minutes (from first to latest activity)
• Total Data Size: $(( total_file_size_bytes / 1024 )) KB
• Estimated Tokens: ~$estimated_tokens (rough estimate: filesize/4)
• Average Messages/Session: $((total_messages_today / (session_count > 0 ? session_count : 1)))

PROJECT BREAKDOWN:
==================
$(printf "• %s\n" "${unique_projects[@]}")

SESSION TIMING:
===============
• First Activity: $earliest_session_time
• Latest Activity: $latest_session_time
• Active Time Span: $total_session_duration_minutes minutes

POTENTIAL CAUSES FOR EARLY LIMIT TRIGGER:
==========================================
- Token counting may include system/hidden tokens not visible to user
- Conversation context may be larger than displayed message count suggests
- Previous session state may be contributing to token count
- Claude may apply safety margins before advertised limits
- System prompts and tool definitions count toward token usage
- Code blocks and structured data use more tokens than plain text

DEBUGGING STEPS:
================
1. Check session message complexity (code blocks, long responses)
2. Verify if multiple large context files are loaded
3. Look for hidden system prompts or conversation persistence
4. Compare estimated vs actual token usage (check if $estimated_tokens ≈ reported usage)
5. Review if $session_count concurrent sessions might be sharing context
6. Consider if ${#unique_projects[@]} different projects loaded tools/context

SESSION SNAPSHOT: $snapshot_file
ANALYSIS GENERATED: $(date +"%Y-%m-%dT%H:%M:%S %Z") (Local Time)

CLAUDE CLI ENVIRONMENT:
========================
$(get_claude_cli_info)
EOF
    
    print_section "Limit snapshot created:\n• Data: $(basename "$snapshot_file")\n• Analysis: $(basename "$analysis_file")" "warning" "🚨 Limit Debug Snapshot"
    
    # Display summary ceremony with key metrics
    local summary_ceremony=""
    summary_ceremony+="📊 USAGE SUMMARY CEREMONY:\n"
    summary_ceremony+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    summary_ceremony+="🔢 Messages Today: $total_messages_today\n"
    # Convert minutes to hours and minutes for display
    local hours=$((total_session_duration_minutes / 60))
    local minutes=$((total_session_duration_minutes % 60))
    local duration_display="${hours}h ${minutes}m"
    
    summary_ceremony+="⏱️  Session Duration: $duration_display\n"
    summary_ceremony+="📁 Active Sessions: $session_count\n"
    summary_ceremony+="🗂️  Unique Projects: ${#unique_projects[@]}\n"
    summary_ceremony+="💾 Estimated Tokens: ~$estimated_tokens\n"
    summary_ceremony+="📈 Trigger: $limit_type at $current_usage of $limit_value\n"
    summary_ceremony+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    print_section "$summary_ceremony" "info" "📋 Quick Reference"
}

# Show historical snapshots
show_snapshots() {
    ensure_snapshot_dir
    
    local snapshots=$(find "$SNAPSHOT_DIR" -name "snapshot_*.json" -type f | sort -r | head -10)
    
    if [[ -z "$snapshots" ]]; then
        print_section "No snapshots found in $SNAPSHOT_DIR" "warning"
        return 0
    fi
    
    local snapshot_list=""
    snapshot_list+="📸 Recent Snapshots (last 10):\n\n"
    
    while IFS= read -r snapshot_file; do
        if [[ -n "$snapshot_file" ]]; then
            local filename=$(basename "$snapshot_file")
            local filesize=$(du -h "$snapshot_file" | cut -f1)
            local modified=$(stat -f%Sm -t"%Y-%m-%d %H:%M" "$snapshot_file" 2>/dev/null || stat -c%y "$snapshot_file" | cut -d' ' -f1-2)
            
            # Extract snapshot type and trigger from filename
            local snapshot_type=$(echo "$filename" | sed 's/.*_\([^_]*\)\.json/\1/')
            
            snapshot_list+="• $filename ($filesize) - $modified - Type: $snapshot_type\n"
        fi
    done <<< "$snapshots"
    
    print_section "$snapshot_list" "info" "📊 Historical Snapshots"
}

# Compare snapshots for trend analysis
compare_snapshots() {
    local snapshot1="$1"
    local snapshot2="$2"
    
    if [[ ! -f "$SNAPSHOT_DIR/$snapshot1" ]] || [[ ! -f "$SNAPSHOT_DIR/$snapshot2" ]]; then
        print_section "Snapshot files not found. Use 'snapshots' command to see available files." "error"
        return 1
    fi
    
    local file1="$SNAPSHOT_DIR/$snapshot1"
    local file2="$SNAPSHOT_DIR/$snapshot2"
    
    # Extract key metrics for comparison
    local messages1=$(grep '"total_messages_today":' "$file1" | sed 's/.*: *\([0-9]*\).*/\1/')
    local sessions1=$(grep '"active_sessions_24h":' "$file1" | sed 's/.*: *\([0-9]*\).*/\1/')
    local messages2=$(grep '"total_messages_today":' "$file2" | sed 's/.*: *\([0-9]*\).*/\1/')
    local sessions2=$(grep '"active_sessions_24h":' "$file2" | sed 's/.*: *\([0-9]*\).*/\1/')
    
    local comparison=""
    comparison+="📊 Snapshot Comparison:\n\n"
    comparison+="Snapshot 1: $snapshot1\n"
    comparison+="• Messages: $messages1\n"
    comparison+="• Sessions: $sessions1\n\n"
    comparison+="Snapshot 2: $snapshot2\n" 
    comparison+="• Messages: $messages2\n"
    comparison+="• Sessions: $sessions2\n\n"
    # Calculate changes safely
    local msg_change=$((messages2 - messages1))
    local sess_change=$((sessions2 - sessions1))
    local msg_direction="no change"
    local sess_direction="no change"
    
    if [[ $msg_change -gt 0 ]]; then
        msg_direction="increase"
    elif [[ $msg_change -lt 0 ]]; then
        msg_direction="decrease"
    fi
    
    if [[ $sess_change -gt 0 ]]; then
        sess_direction="increase"
    elif [[ $sess_change -lt 0 ]]; then
        sess_direction="decrease"
    fi
    
    comparison+="Changes:\n"
    comparison+="• Messages: $msg_change ($msg_direction)\n"
    comparison+="• Sessions: $sess_change ($sess_direction)\n"
    
    print_section "$comparison" "info" "📈 Trend Analysis"
}

# Get Claude CLI version and environment info
get_claude_cli_info() {
    local claude_version="Unknown"
    local claude_path="Not found"
    local last_updated="Unknown"
    
    # Try to find claude CLI and get version
    if command -v claude >/dev/null 2>&1; then
        claude_path=$(which claude)
        claude_version=$(claude --version 2>/dev/null || echo "Version command failed")
        
        # Get last modification time of claude binary (approximates last update)
        if [[ -f "$claude_path" ]]; then
            last_updated=$(stat -f%Sm -t"%Y-%m-%d %H:%M" "$claude_path" 2>/dev/null || stat -c%y "$claude_path" 2>/dev/null | cut -d' ' -f1-2 || echo "Unknown")
        fi
    fi
    
    cat << EOF
• Claude CLI Version: $claude_version
• Claude CLI Path: $claude_path
• Last Updated: $last_updated
• Projects Directory: $PROJECTS_DIR
• Config Directory: $CONFIG_DIR
EOF
}

# Command help
show_help() {
    print_header "Claude Usage Monitor v2.0 - CORRECTED Implementation" "info"
    
    local help_text=""
    help_text+="🎯 FEATURES + SNAPSHOT SYSTEM:\n"
    help_text+="  dashboard        Complete usage analysis with JSON timestamp parsing\n"
    help_text+="  status          Current session status using actual JSON timestamps\n"
    help_text+="  patterns        Usage patterns based on JSON content analysis\n"
    help_text+="  snap/snapshot   Create manual usage snapshot for historical analysis\n"
    help_text+="  snapshots       Show recent snapshots with metadata\n"
    help_text+="  compare <s1> <s2>  Compare two snapshots for trend analysis\n"
    help_text+="  snaptok/snapshot-token-limit [usage] [limit]  Debug token limits\n"
    help_text+="  snaptime/snapshot-time-limit [usage] [limit]  Debug time limits\n\n"
    
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
        "snap"|"snapshot")
            snapshot_file=$(create_usage_snapshot "manual" "user_requested")
            print_section "Manual snapshot created: $(basename "$snapshot_file")" "success" "📸 Snapshot Created"
            ;;
        "snapshots")
            show_snapshots
            ;;
        "compare")
            if [[ $# -lt 3 ]]; then
                print_section "Usage: ccuse compare <snapshot1> <snapshot2>\nUse 'snapshots' command to see available files." "error"
                exit 1
            fi
            compare_snapshots "$2" "$3"
            ;;
        "snaptok"|"snapshot-token-limit")
            create_limit_snapshot "token" "${2:-70%}" "${3:-200k}"
            ;;
        "snaptime"|"snapshot-time-limit")
            create_limit_snapshot "time" "${2:-unknown}" "${3:-daily}"
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
