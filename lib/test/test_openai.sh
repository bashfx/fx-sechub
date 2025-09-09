#!/bin/bash
# OpenAI API Test Script
# Tests both free and usage-impacting endpoints

set -euo pipefail

# Configuration
API_KEY_FILE="$HOME/.codex/auth.json"
LOG_FILE="$HOME/openai_test_$(date +%Y%m%d_%H%M%S).log"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_message() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Get API key
get_api_key() {
    if [ ! -f "$API_KEY_FILE" ]; then
        echo "Error: API key file not found at $API_KEY_FILE"
        exit 1
    fi
    
    local key=$(jq -r '.OPENAI_API_KEY // empty' "$API_KEY_FILE" 2>/dev/null)
    if [ -z "$key" ] || [ "$key" == "null" ]; then
        echo "Error: No valid API key found"
        exit 1
    fi
    
    echo "$key"
}

# Test free endpoints
test_free_endpoints() {
    local api_key="$1"
    
    echo -e "${BLUE}=== Testing OpenAI Free Endpoints ===${NC}"
    log_message "Starting free endpoint tests"
    
    # Organization info
    echo "Testing organization info..."
    local org_response=$(curl -s -H "Authorization: Bearer $api_key" \
        "https://api.openai.com/v1/organization" || echo '{"error": "failed"}')
    
    if echo "$org_response" | jq -e '.name' >/dev/null 2>&1; then
        local org_name=$(echo "$org_response" | jq -r '.name')
        echo -e "${GREEN}✓ Organization: $org_name${NC}"
        log_message "Organization test: SUCCESS ($org_name)"
    else
        echo -e "${RED}✗ Organization test failed${NC}"
        log_message "Organization test: FAILED"
    fi
    
    # Models list
    echo "Testing models list..."
    local models_response=$(curl -s -H "Authorization: Bearer $api_key" \
        "https://api.openai.com/v1/models" || echo '{"error": "failed"}')
    
    if echo "$models_response" | jq -e '.data' >/dev/null 2>&1; then
        local model_count=$(echo "$models_response" | jq '.data | length')
        echo -e "${GREEN}✓ Available models: $model_count${NC}"
        log_message "Models test: SUCCESS ($model_count models)"
        
        # List GPT-4 models
        local gpt4_models=$(echo "$models_response" | jq -r '.data[] | select(.id | contains("gpt-4")) | .id' | head -3)
        if [ -n "$gpt4_models" ]; then
            echo -e "${BLUE}GPT-4 models available:${NC}"
            echo "$gpt4_models" | while read model; do
                echo "  - $model"
            done
        fi
    else
        echo -e "${RED}✗ Models test failed${NC}"
        log_message "Models test: FAILED"
    fi
}

# Test usage-impacting endpoints (minimal usage)
test_usage_endpoints() {
    local api_key="$1"
    
    echo -e "\n${YELLOW}=== Testing OpenAI Usage-Impacting Endpoints (Minimal) ===${NC}"
    echo -e "${YELLOW}WARNING: These tests will consume small amounts of your quota${NC}"
    log_message "Starting usage-impacting endpoint tests"
    
    # GPT-3.5 minimal test
    echo "Testing GPT-3.5 Turbo (1 token)..."
    local gpt35_response=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
        -H "Authorization: Bearer $api_key" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "gpt-3.5-turbo",
            "messages": [{"role": "user", "content": "Hi"}],
            "max_tokens": 1
        }' \
        "https://api.openai.com/v1/chat/completions" || echo 'ERROR')
    
    local http_code=$(echo "$gpt35_response" | grep "HTTP_CODE:" | cut -d: -f2)
    local response_body=$(echo "$gpt35_response" | sed '/HTTP_CODE:/d')
    
    if [ "$http_code" == "200" ]; then
        local usage=$(echo "$response_body" | jq -r '.usage // "unknown"' 2>/dev/null)
        echo -e "${GREEN}✓ GPT-3.5 test: SUCCESS${NC}"
        echo -e "${BLUE}Usage: $usage${NC}"
        log_message "GPT-3.5 test: SUCCESS - Usage: $usage"
    else
        echo -e "${RED}✗ GPT-3.5 test failed (HTTP $http_code)${NC}"
        log_message "GPT-3.5 test: FAILED (HTTP $http_code)"
        
        # Check for rate limiting
        if [ "$http_code" == "429" ]; then
            echo -e "${YELLOW}Rate limited - this is expected behavior${NC}"
        fi
    fi
    
    # GPT-4 minimal test (if available)
    echo "Testing GPT-4 access (1 token)..."
    local gpt4_response=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
        -H "Authorization: Bearer $api_key" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "gpt-4",
            "messages": [{"role": "user", "content": "Hi"}],
            "max_tokens": 1
        }' \
        "https://api.openai.com/v1/chat/completions" || echo 'ERROR')
    
    local gpt4_http_code=$(echo "$gpt4_response" | grep "HTTP_CODE:" | cut -d: -f2)
    local gpt4_body=$(echo "$gpt4_response" | sed '/HTTP_CODE:/d')
    
    if [ "$gpt4_http_code" == "200" ]; then
        local gpt4_usage=$(echo "$gpt4_body" | jq -r '.usage // "unknown"' 2>/dev/null)
        echo -e "${GREEN}✓ GPT-4 test: SUCCESS${NC}"
        echo -e "${BLUE}Usage: $gpt4_usage${NC}"
        log_message "GPT-4 test: SUCCESS - Usage: $gpt4_usage"
    else
        echo -e "${RED}✗ GPT-4 test failed (HTTP $gpt4_http_code)${NC}"
        log_message "GPT-4 test: FAILED (HTTP $gpt4_http_code)"
        
        if [ "$gpt4_http_code" == "429" ]; then
            echo -e "${YELLOW}Rate limited${NC}"
        elif [ "$gpt4_http_code" == "403" ]; then
            echo -e "${YELLOW}Access denied - GPT-4 may not be available on your plan${NC}"
        fi
    fi
}

# Check rate limits
check_rate_limits() {
    local api_key="$1"
    
    echo -e "\n${BLUE}=== Checking Rate Limits ===${NC}"
    log_message "Checking rate limit headers"
    
    local rate_response=$(curl -s -I -H "Authorization: Bearer $api_key" \
        "https://api.openai.com/v1/models" || echo 'failed')
    
    if [ "$rate_response" != "failed" ]; then
        # Extract rate limit headers
        local limit_requests=$(echo "$rate_response" | grep -i "x-ratelimit-limit-requests" | cut -d: -f2 | tr -d ' \r' || echo "unknown")
        local remaining_requests=$(echo "$rate_response" | grep -i "x-ratelimit-remaining-requests" | cut -d: -f2 | tr -d ' \r' || echo "unknown")
        local reset_requests=$(echo "$rate_response" | grep -i "x-ratelimit-reset-requests" | cut -d: -f2 | tr -d ' \r' || echo "unknown")
        
        if [ "$limit_requests" != "unknown" ]; then
            echo -e "${BLUE}Request limits: $remaining_requests/$limit_requests${NC}"
            echo -e "${BLUE}Reset time: $reset_requests${NC}"
            log_message "Rate limits: $remaining_requests/$limit_requests, reset: $reset_requests"
        else
            echo -e "${YELLOW}Rate limit headers not found${NC}"
            log_message "No rate limit headers detected"
        fi
    fi
}

# Monitor network activity
monitor_network() {
    echo -e "\n${BLUE}=== Network Activity Check ===${NC}"
    log_message "Checking network activity"
    
    # Check active connections
    local connections=$(netstat -tupln 2>/dev/null | grep "api.openai.com" || echo "")
    if [ -n "$connections" ]; then
        echo -e "${YELLOW}Active OpenAI connections detected:${NC}"
        echo "$connections"
        log_message "Active connections found"
    else
        echo -e "${GREEN}No active OpenAI connections${NC}"
        log_message "No active connections"
    fi
    
    # Check for OpenAI-related processes
    local processes=$(ps aux | grep -E "(curl.*openai|python.*openai|codex)" | grep -v grep || echo "")
    if [ -n "$processes" ]; then
        echo -e "${YELLOW}OpenAI-related processes:${NC}"
        echo "$processes"
        log_message "OpenAI processes detected"
    else
        echo -e "${GREEN}No OpenAI processes detected${NC}"
        log_message "No OpenAI processes"
    fi
}

# Main execution
main() {
    echo "OpenAI API Test Script - $(date)"
    echo "=================================="
    
    local api_key
    api_key=$(get_api_key)
    
    # Run tests
    test_free_endpoints "$api_key"
    test_usage_endpoints "$api_key"
    check_rate_limits "$api_key"
    monitor_network
    
    echo -e "\n${BLUE}Test completed. Log file: $LOG_FILE${NC}"
    echo -e "${YELLOW}Note: Minimal usage tests consumed small amounts of your quota${NC}"
}

main "$@"