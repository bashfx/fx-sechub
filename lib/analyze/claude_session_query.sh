#!/bin/bash
# claude_session_query.sh - Query Claude session data with useful patterns
# Generated: 2025-09-06
# Purpose: Provide jq-like query patterns for Claude session analysis

set -e

CLAUDE_DIR="$HOME/.claude"
PROJECTS_DIR="$CLAUDE_DIR/projects"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

usage() {
    echo -e "${BLUE}Claude Session Query Utility${NC}"
    echo "Usage: $0 [COMMAND] [SESSION_FILE|SESSION_ID]"
    echo ""
    echo "Commands:"
    echo "  metadata SESSION     - Show session metadata (duration, messages, models)"
    echo "  tokens SESSION       - Analyze token usage patterns"
    echo "  timeline SESSION     - Show conversation timeline"
    echo "  models SESSION       - List models used in session"
    echo "  cache SESSION        - Analyze cache usage patterns"
    echo "  tools SESSION        - Show tool usage in session"
    echo "  errors SESSION       - Find errors and failures"
    echo "  search SESSION TEXT  - Search for text in conversation"
    echo "  list                 - List all available sessions"
    echo "  recent [N]           - Show N most recent sessions (default 10)"
    echo ""
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 recent 5"
    echo "  $0 metadata 5e630e19-3965-47ac-b626-f912454c6a09"
    echo "  $0 tokens current"
    echo "  $0 search current 'security'"
}

find_session_file() {
    local input="$1"
    
    # If it's already a file path, use it
    if [[ -f "$input" ]]; then
        echo "$input"
        return 0
    fi
    
    # If it's "current", find most recent session
    if [[ "$input" == "current" ]]; then
        find "$PROJECTS_DIR" -name "*.jsonl" -printf "%T@ %p\n" | sort -nr | head -1 | cut -d' ' -f2
        return 0
    fi
    
    # If it looks like a session ID, find the file
    if [[ "$input" =~ ^[a-f0-9-]+$ ]]; then
        find "$PROJECTS_DIR" -name "*$input*.jsonl" | head -1
        return 0
    fi
    
    # Try as partial match
    find "$PROJECTS_DIR" -name "*$input*.jsonl" | head -1
}

list_sessions() {
    echo -e "${GREEN}Available Sessions:${NC}"
    find "$PROJECTS_DIR" -name "*.jsonl" -printf "%T+ %p\n" | sort -r | head -20 | while read timestamp path; do
        local session_id=$(basename "$path" .jsonl)
        local project=$(basename "$(dirname "$path")")
        local readable_time=$(date -d "${timestamp%.*}" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$timestamp")
        local size=$(stat -f%z "$path" 2>/dev/null || stat -c%s "$path" 2>/dev/null || echo "?")
        local messages=$(wc -l < "$path" 2>/dev/null || echo "?")
        
        printf "%-16s %-30s %s (%s msgs, %s bytes)\n" \
            "$readable_time" \
            "${project:0:30}" \
            "${session_id:0:36}" \
            "$messages" \
            "$size"
    done
}

recent_sessions() {
    local count="${1:-10}"
    echo -e "${GREEN}$count Most Recent Sessions:${NC}"
    find "$PROJECTS_DIR" -name "*.jsonl" -printf "%T@ %p\n" | sort -nr | head "$count" | while read timestamp path; do
        local session_id=$(basename "$path" .jsonl)
        local project=$(basename "$(dirname "$path")")
        local readable_time=$(date -d "@${timestamp%.*}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
        echo "$readable_time - $project - $session_id"
    done
}

session_metadata() {
    local session_file="$1"
    
    if [[ ! -f "$session_file" ]]; then
        echo -e "${RED}Session file not found: $session_file${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Session Metadata:${NC}"
    echo "File: $session_file"
    
    # Basic stats
    local total_lines=$(wc -l < "$session_file")
    local file_size=$(stat -f%z "$session_file" 2>/dev/null || stat -c%s "$session_file" 2>/dev/null)
    
    echo "Messages: $total_lines"
    echo "File Size: $file_size bytes"
    
    # Session info from first message
    local session_info=$(head -1 "$session_file" | jq -r '
        if .sessionId then
            "Session ID: " + .sessionId + "\n" +
            "CLI Version: " + (.version // "unknown") + "\n" +
            "Working Dir: " + (.cwd // "unknown") + "\n" +
            "Git Branch: " + (.gitBranch // "none")
        else
            "Summary entry (no session metadata)"
        end' 2>/dev/null)
    echo "$session_info"
    
    # Time range
    local start_time=$(head -1 "$session_file" | jq -r '.timestamp // empty' 2>/dev/null)
    local end_time=$(tail -1 "$session_file" | jq -r '.timestamp // empty' 2>/dev/null)
    
    if [[ -n "$start_time" && "$start_time" != "null" && -n "$end_time" && "$end_time" != "null" ]]; then
        local start_readable=$(date -d "$start_time" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || echo "$start_time")
        local end_readable=$(date -d "$end_time" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || echo "$end_time")
        echo "Started: $start_readable"
        echo "Ended: $end_readable"
        
        # Calculate duration
        local start_epoch=$(date -d "$start_time" +%s 2>/dev/null)
        local end_epoch=$(date -d "$end_time" +%s 2>/dev/null)
        if [[ -n "$start_epoch" && -n "$end_epoch" ]]; then
            local duration=$((end_epoch - start_epoch))
            local hours=$((duration / 3600))
            local minutes=$(((duration % 3600) / 60))
            echo "Duration: ${hours}h ${minutes}m"
        fi
    fi
}

analyze_tokens() {
    local session_file="$1"
    
    if [[ ! -f "$session_file" ]]; then
        echo -e "${RED}Session file not found: $session_file${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Token Usage Analysis:${NC}"
    
    # Total tokens
    local total_input=$(grep '"input_tokens"' "$session_file" 2>/dev/null | jq '.message.usage.input_tokens // 0' | awk '{sum+=$1} END {print sum+0}')
    local total_output=$(grep '"output_tokens"' "$session_file" 2>/dev/null | jq '.message.usage.output_tokens // 0' | awk '{sum+=$1} END {print sum+0}')
    local total_cache_read=$(grep '"cache_read_input_tokens"' "$session_file" 2>/dev/null | jq '.message.usage.cache_read_input_tokens // 0' | awk '{sum+=$1} END {print sum+0}')
    local total_cache_creation=$(grep '"cache_creation_input_tokens"' "$session_file" 2>/dev/null | jq '.message.usage.cache_creation_input_tokens // 0' | awk '{sum+=$1} END {print sum+0}')
    
    echo "Total Input Tokens: $total_input"
    echo "Total Output Tokens: $total_output"  
    echo "Total Cache Read: $total_cache_read"
    echo "Total Cache Creation: $total_cache_creation"
    echo "Total Tokens: $((total_input + total_output))"
    
    # Cache efficiency
    if [[ $total_input -gt 0 ]]; then
        local cache_ratio=$(echo "scale=1; $total_cache_read * 100 / $total_input" | bc 2>/dev/null || echo "0")
        echo "Cache Hit Rate: ${cache_ratio}%"
    fi
    
    # Top token consuming messages
    echo -e "\n${YELLOW}Top 5 Token Consuming Responses:${NC}"
    grep '"usage":' "$session_file" 2>/dev/null | jq -r '
        .message.usage as $usage |
        .timestamp as $time |
        .message.model as $model |
        [($usage.input_tokens // 0), ($usage.output_tokens // 0), $time, $model] |
        @tsv' | sort -nr | head -5 | while IFS=$'\t' read input output time model; do
        local readable_time=$(date -d "$time" '+%H:%M:%S' 2>/dev/null || echo "${time:11:8}")
        printf "%s - %s: %s in / %s out\n" "$readable_time" "${model:-unknown}" "$input" "$output"
    done
}

show_timeline() {
    local session_file="$1"
    
    if [[ ! -f "$session_file" ]]; then
        echo -e "${RED}Session file not found: $session_file${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Conversation Timeline:${NC}"
    
    jq -r '
        select(.timestamp and .message and .type) |
        if .type == "user" then
            (.timestamp | strftime("%H:%M:%S")) + " [USER] " + 
            ((.message.content | type) as $type |
             if $type == "string" then
                 .message.content[:100] + (if (.message.content | length) > 100 then "..." else "" end)
             else
                 "Tool use/response"
             end)
        elif .type == "assistant" then
            (.timestamp | strftime("%H:%M:%S")) + " [" + (.message.model // "AI") + "] " +
            (if .message.content then
                 (if (.message.content | type) == "array" then
                     (.message.content[] | select(.type == "text") | .text)[:100]
                 else
                     (.message.content | tostring)[:100]
                 end) + (if (.message.content | tostring | length) > 100 then "..." else "" end)
             else
                 "No content"
             end)
        else
            (.timestamp | strftime("%H:%M:%S")) + " [" + .type + "] " + (.message.content // "")[:50]
        end
    ' "$session_file" 2>/dev/null | head -50
}

show_models() {
    local session_file="$1"
    
    if [[ ! -f "$session_file" ]]; then
        echo -e "${RED}Session file not found: $session_file${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Models Used:${NC}"
    
    jq -r 'select(.message.model) | .message.model' "$session_file" 2>/dev/null | sort | uniq -c | sort -nr | while read count model; do
        echo "$count requests - $model"
    done
}

search_conversation() {
    local session_file="$1"
    local search_text="$2"
    
    if [[ ! -f "$session_file" ]]; then
        echo -e "${RED}Session file not found: $session_file${NC}"
        return 1
    fi
    
    if [[ -z "$search_text" ]]; then
        echo -e "${RED}Search text required${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Search Results for '$search_text':${NC}"
    
    jq -r --arg search "$search_text" '
        select(.message.content | tostring | test($search; "i")) |
        (.timestamp | strftime("%H:%M:%S")) + " [" + .type + "] " +
        (.message.content | tostring)
    ' "$session_file" 2>/dev/null | grep -i --color=always "$search_text"
}

# Main command dispatch
case "${1:-}" in
    "list")
        list_sessions
        ;;
    "recent")
        recent_sessions "$2"
        ;;
    "metadata")
        session_file=$(find_session_file "$2")
        session_metadata "$session_file"
        ;;
    "tokens")
        session_file=$(find_session_file "$2")
        analyze_tokens "$session_file"
        ;;
    "timeline")
        session_file=$(find_session_file "$2")
        show_timeline "$session_file"
        ;;
    "models")
        session_file=$(find_session_file "$2")
        show_models "$session_file"
        ;;
    "search")
        session_file=$(find_session_file "$2")
        search_conversation "$session_file" "$3"
        ;;
    *)
        usage
        ;;
esac