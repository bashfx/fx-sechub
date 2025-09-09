#!/bin/bash
# Anthropic Claude API Test Script
# Tests usage-impacting endpoints (Claude has fewer free endpoints)

set -euo pipefail

# Configuration
CREDENTIALS_FILE="$HOME/.claude/.credentials.json"
LOG_FILE="$HOME/claude_test_$(date +%Y%m%d_%H%M%S).log"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_message() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Get access token
get_access_token() {
    if [ ! -f "$CREDENTIALS_FILE" ]; then
        echo "Error: Credentials file not found at $CREDENTIALS_FILE"
        echo "Make sure you're authenticated with Claude"
        exit 1
    fi
    
    local token=$(jq -r '.claudeAiOauth.accessToken // empty' "$CREDENTIALS_FILE" 2>/dev/null)
    if [ -z "$token" ] || [ "$token" == "null" ]; then
        echo "Error: No valid access token found"
        exit 1
    fi
    
    # Check token expiry
    local expires_at=$(jq -r '.claudeAiOauth.expiresAt // 0' "$CREDENTIALS_FILE" 2>/dev/null)
    local current_time=$(date +%s)
    
    if [ "$expires_at" -gt 9999999999 ]; then
        expires_at=$((expires_at / 1000))
    fi
    
    if [ "$current_time" -gt "$expires_at" ]; then
        echo "Error: Token expired"
        exit 1
    fi
    
    echo "$token"
}

# Check subscription info
check_subscription() {
    echo -e "${BLUE}=== Claude Max Subscription Info ===${NC}"
    log_message "Checking subscription information"
    
    local subscription=$(jq -r '.claudeAiOauth.subscriptionType // "unknown"' "$CREDENTIALS_FILE" 2>/dev/null)
    local scopes=$(jq -r '.claudeAiOauth.scopes // [] | join(", ")' "$CREDENTIALS_FILE" 2>/dev/null)
    local expires_at=$(jq -r '.claudeAiOauth.expiresAt // 0' "$CREDENTIALS_FILE" 2>/dev/null)
    
    echo -e "${GREEN}Subscription: $subscription${NC}"
    echo -e "${BLUE}Scopes: $scopes${NC}"
    log_message "Subscription: $subscription, Scopes: $scopes"
    
    # Calculate token expiry
    if [ "$expires_at" -gt 0 ]; then
        local current_time=$(date +%s)
        if [ "$expires_at" -gt 9999999999 ]; then
            expires_at=$((expires_at / 1000))
        fi
        local hours_until_expiry=$(( (expires_at - current_time) / 3600 ))
        echo -e "${BLUE}Token expires in: $hours_until_expiry hours${NC}"
        log_message "Token expires in $hours_until_expiry hours"
    fi
}

# Test Claude models (usage-impacting)
test_claude_models() {
    local access_token="$1"
    
    echo -e "\n${YELLOW}=== Testing Claude Models (Minimal Usage) ===${NC}"
    echo -e "${YELLOW}WARNING: These tests will consume your Claude Max quota${NC}"
    log_message "Starting Claude model tests"
    
    # Test Claude Haiku (fastest/cheapest)
    echo "Testing Claude 3 Haiku (1 token)..."
    local haiku_response=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        -H "anthropic-version: 2023-06-01" \
        -d '{
            "model": "claude-3-haiku-20240307",
            "max_tokens": 1,
            "messages": [
                {"role": "user", "content": "Hi"}
            ]
        }' \
        "https://api.anthropic.com/v1/messages" || echo 'ERROR')
    
    local http_code=$(echo "$haiku_response" | grep "HTTP_CODE:" | cut -d: -f2)
    local response_body=$(echo "$haiku_response" | sed '/HTTP_CODE:/d')
    
    if [ "$http_code" == "200" ]; then
        local content=$(echo "$response_body" | jq -r '.content[0].text // "No content"' 2>/dev/null)
        local input_tokens=$(echo "$response_body" | jq -r '.usage.input_tokens // 0' 2>/dev/null)
        local output_tokens=$(echo "$response_body" | jq -r '.usage.output_tokens // 0' 2>/dev/null)
        local model=$(echo "$response_body" | jq -r '.model // "unknown"' 2>/dev/null)
        
        echo -e "${GREEN}✓ Claude Haiku test: SUCCESS${NC}"
        echo -e "${BLUE}Model: $model${NC}"
        echo -e "${BLUE}Response: $content${NC}"
        echo -e "${BLUE}Usage: Input=$input_tokens, Output=$output_tokens tokens${NC}"
        log_message "Haiku test: SUCCESS - Usage: $input_tokens/$output_tokens tokens"
    else
        echo -e "${RED}✗ Claude Haiku test failed (HTTP $http_code)${NC}"
        log_message "Haiku test: FAILED (HTTP $http_code)"
        
        # Parse error details
        local error_type=$(echo "$response_body" | jq -r '.error.type // "unknown"' 2>/dev/null)
        local error_message=$(echo "$response_body" | jq -r '.error.message // "No error message"' 2>/dev/null)
        
        echo -e "${RED}Error type: $error_type${NC}"
        echo -e "${RED}Error message: $error_message${NC}"
        log_message "Error: $error_type - $error_message"
        
        # Check specific error conditions
        if [[ "$error_type" == "authentication_error" ]]; then
            echo -e "${YELLOW}Authentication issue detected${NC}"
        elif [[ "$error_type" == "rate_limit_error" ]]; then
            echo -e "${YELLOW}Rate limit exceeded${NC}"
        elif [[ "$error_type" == "billing_error" ]]; then
            echo -e "${YELLOW}Billing/quota issue${NC}"
        fi
    fi
    
    # Test Claude Sonnet (mid-tier) - only if Haiku succeeded
    if [ "$http_code" == "200" ]; then
        echo "Testing Claude 3 Sonnet (1 token)..."
        local sonnet_response=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
            -H "Authorization: Bearer $access_token" \
            -H "Content-Type: application/json" \
            -H "anthropic-version: 2023-06-01" \
            -d '{
                "model": "claude-3-sonnet-20240229",
                "max_tokens": 1,
                "messages": [
                    {"role": "user", "content": "Test"}
                ]
            }' \
            "https://api.anthropic.com/v1/messages" || echo 'ERROR')
        
        local sonnet_http_code=$(echo "$sonnet_response" | grep "HTTP_CODE:" | cut -d: -f2)
        local sonnet_body=$(echo "$sonnet_response" | sed '/HTTP_CODE:/d')
        
        if [ "$sonnet_http_code" == "200" ]; then
            local sonnet_usage=$(echo "$sonnet_body" | jq -r '.usage // "unknown"' 2>/dev/null)
            local sonnet_model=$(echo "$sonnet_body" | jq -r '.model // "unknown"' 2>/dev/null)
            echo -e "${GREEN}✓ Claude Sonnet test: SUCCESS${NC}"
            echo -e "${BLUE}Model: $sonnet_model${NC}"
            echo -e "${BLUE}Usage: $sonnet_usage${NC}"
            log_message "Sonnet test: SUCCESS - Usage: $sonnet_usage"
        else
            echo -e "${RED}✗ Claude Sonnet test failed (HTTP $sonnet_http_code)${NC}"
            log_message "Sonnet test: FAILED (HTTP $sonnet_http_code)"
        fi
    else
        echo -e "${YELLOW}Skipping Sonnet test due to Haiku failure${NC}"
    fi
}

# Test conversation context
test_conversation_context() {
    local access_token="$1"
    
    echo -e "\n${YELLOW}Testing conversation context (2 messages)...${NC}"
    log_message "Testing conversation context"
    
    local context_response=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        -H "anthropic-version: 2023-06-01" \
        -d '{
            "model": "claude-3-haiku-20240307",
            "max_tokens": 5,
            "messages": [
                {"role": "user", "content": "My name is Test"},
                {"role": "assistant", "content": "Hello Test!"},
                {"role": "user", "content": "What is my name?"}
            ]
        }' \
        "https://api.anthropic.com/v1/messages" || echo 'ERROR')
    
    local context_http_code=$(echo "$context_response" | grep "HTTP_CODE:" | cut -d: -f2)
    local context_body=$(echo "$context_response" | sed '/HTTP_CODE:/d')
    
    if [ "$context_http_code" == "200" ]; then
        local context_content=$(echo "$context_body" | jq -r '.content[0].text // "No content"' 2>/dev/null)
        local context_usage=$(echo "$context_body" | jq -r '.usage // "unknown"' 2>/dev/null)
        
        echo -e "${GREEN}✓ Context test: SUCCESS${NC}"
        echo -e "${BLUE}Response: $context_content${NC}"
        echo -e "${BLUE}Usage: $context_usage${NC}"
        log_message "Context test: SUCCESS - Response: $context_content"
    else
        echo -e "${RED}✗ Context test failed (HTTP $context_http_code)${NC}"
        log_message "Context test: FAILED"
    fi
}

# Check API health and status
check_api_status() {
    local access_token="$1"
    
    echo -e "\n${BLUE}=== API Health Check ===${NC}"
    log_message "Checking API health"
    
    # Test a minimal request to check API availability
    local health_response=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
        -H "Authorization: Bearer $access_token" \
        -H "anthropic-version: 2023-06-01" \
        "https://api.anthropic.com/v1/messages" -d '{}' || echo 'ERROR')
    
    local health_code=$(echo "$health_response" | grep "HTTP_CODE:" | cut -d: -f2)
    
    # We expect this to fail with 400 (bad request) but not 401/403/500
    if [ "$health_code" == "400" ]; then
        echo -e "${GREEN}API endpoint reachable (expected 400 for empty request)${NC}"
        log_message "API health: Good"
    elif [ "$health_code" == "401" ]; then
        echo -e "${RED}Authentication failed${NC}"
        log_message "API health: Auth failed"
    elif [ "$health_code" == "403" ]; then
        echo -e "${RED}Access forbidden${NC}"
        log_message "API health: Access denied"
    elif [ "$health_code" == "500" ] || [ "$health_code" == "502" ] || [ "$health_code" == "503" ]; then
        echo -e "${RED}API server error (${health_code})${NC}"
        log_message "API health: Server error $health_code"
    else
        echo -e "${YELLOW}Unexpected response code: $health_code${NC}"
        log_message "API health: Unexpected code $health_code"
    fi
}

# Monitor network activity
monitor_network() {
    echo -e "\n${BLUE}=== Network Activity Check ===${NC}"
    log_message "Checking network activity"
    
    # Check active connections
    local connections=$(netstat -tupln 2>/dev/null | grep "anthropic" || echo "")
    if [ -n "$connections" ]; then
        echo -e "${YELLOW}Active Anthropic connections:${NC}"
        echo "$connections"
        log_message "Active connections found"
    else
        echo -e "${GREEN}No active Anthropic connections${NC}"
        log_message "No active connections"
    fi
    
    # Check for Claude-related processes
    local processes=$(ps aux | grep -E "(curl.*anthropic|claude)" | grep -v grep || echo "")
    if [ -n "$processes" ]; then
        echo -e "${YELLOW}Claude-related processes:${NC}"
        echo "$processes"
        log_message "Claude processes detected"
    else
        echo -e "${GREEN}No Claude processes detected${NC}"
        log_message "No Claude processes"
    fi
}

# Main execution
main() {
    echo "Anthropic Claude API Test Script - $(date)"
    echo "===========================================" 
    
    local access_token
    access_token=$(get_access_token)
    
    # Run tests
    check_subscription
    check_api_status "$access_token"
    test_claude_models "$access_token"
    test_conversation_context "$access_token"
    monitor_network
    
    echo -e "\n${BLUE}Test completed. Log file: $LOG_FILE${NC}"
    echo -e "${YELLOW}Note: All Claude tests consume your Max subscription quota${NC}"
    echo -e "${GREEN}Claude Max has higher limits than Pro, but quota is still finite${NC}"
}

main "$@"