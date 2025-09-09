#!/bin/bash
# DEMONSTRATION: Correct timestamp-based session analysis
# This shows the proper way to analyze sessions based on JSON content timestamps

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
PROJECTS_DIR="$CLAUDE_DIR/projects"

# Correct approach: Parse JSON timestamps from content
find_sessions_by_json_timestamps() {
    local hours_back="${1:-1}"
    local cutoff_epoch=$(date -d "$hours_back hours ago" +%s)
    
    echo "=== Analyzing Sessions by JSON Content Timestamps ==="
    echo "Cutoff time: $(date -d "$hours_back hours ago")"
    echo "Looking for sessions with activity since then..."
    echo
    
    local active_sessions=""
    
    # Find all session files
    for session_file in $(find "$PROJECTS_DIR" -name "*.jsonl" -type f 2>/dev/null); do
        if [ -f "$session_file" ]; then
            # Get the most recent timestamp from this session
            local latest_timestamp=$(timeout 5s tail -5 "$session_file" | jq -r '.timestamp // empty' 2>/dev/null | grep -v '^$' | tail -1 || echo "")
            
            if [[ -n "$latest_timestamp" ]]; then
                # Convert JSON timestamp to epoch for comparison
                local session_epoch=$(date -d "$latest_timestamp" +%s 2>/dev/null || echo 0)
                
                if [[ "$session_epoch" -gt "$cutoff_epoch" ]]; then
                    local project_name=$(basename "$(dirname "$session_file")" | sed 's/-home-xnull-repos-/-/' | sed 's/-/\//g')
                    local session_id=$(basename "$session_file" .jsonl)
                    local minutes_ago=$(( ($(date +%s) - session_epoch) / 60 ))
                    
                    echo "ACTIVE: $project_name - ${session_id:0:8} (${minutes_ago}m ago)"
                    echo "  Latest timestamp: $latest_timestamp"
                    
                    active_sessions+="$session_file\n"
                fi
            fi
        fi
    done
    
    local count=$(echo -e "$active_sessions" | grep -c . 2>/dev/null || echo 0)
    echo
    echo "Total active sessions found: $count"
}

# Test the correct approach
echo "Testing JSON-based timestamp analysis:"
find_sessions_by_json_timestamps 1

echo
echo "=== Comparison with file system approach ==="
echo "File system modification time approach:"
find "$PROJECTS_DIR" -name "*.jsonl" -type f -mmin -60 2>/dev/null | wc -l | xargs echo "Files modified in last hour:"

echo
echo "The difference shows why we need to use JSON content timestamps, not file system timestamps!"