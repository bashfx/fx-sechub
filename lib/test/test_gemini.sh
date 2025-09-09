#!/bin/bash
# Google Gemini API Test Script
# Tests both free and usage-impacting endpoints

set -euo pipefail

# Configuration
CREDENTIALS_FILE="$HOME/.gemini/oauth_creds.json"
LOG_FILE="$HOME/gemini_test_$(date +%Y%m%d_%H%M%S).log"

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
        echo "Run: gemini auth"
        exit 1
    fi
    
    local token=$(jq -r '.access_token // empty' "$CREDENTIALS_FILE" 2>/dev/null)
    if [ -z "$token" ] || [ "$token" == "null" ]; then
        echo "Error: No valid access token found"
        echo "Token may be expired. Run: gemini auth"
        exit 1
    fi
    
    # Check token expiry
    local expiry_date=$(jq -r '.expiry_date // 0' "$CREDENTIALS_FILE" 2>/dev/null)
    local current_time=$(date +%s)
    
    if [ "$expiry_date" -gt 9999999999 ]; then
        expiry_date=$((expiry_date / 1000))
    fi
    
    if [ "$current_time" -gt "$expiry_date" ]; then
        echo "Error: Token expired. Run: gemini auth"
        exit 1
    fi
    
    echo "$token"
}

# Test free endpoints
test_free_endpoints() {
    local access_token="$1"
    
    echo -e "${BLUE}=== Testing Gemini Free Endpoints ===${NC}"
    log_message "Starting free endpoint tests"
    
    # Models list
    echo "Testing models list..."
    local models_response=$(curl -s -H "Authorization: Bearer $access_token" \
        "https://generativelanguage.googleapis.com/v1beta/models" || echo '{"error": "failed"}')
    
    if echo "$models_response" | jq -e '.models' >/dev/null 2>&1; then
        local model_count=$(echo "$models_response" | jq '.models | length')
        echo -e "${GREEN}✓ Available models: $model_count${NC}"
        log_message "Models test: SUCCESS ($model_count models)"
        
        # List Gemini models with limits
        echo -e "${BLUE}Gemini models:${NC}"
        echo "$models_response" | jq -r '.models[] | select(.name | contains("gemini")) | "\(.name | split("/")[-1]) - Input: \(.inputTokenLimit // "unknown") tokens"' | head -5 | while read model_info; do
            echo "  - $model_info"
            log_message "Available: $model_info"
        done
    else
        echo -e "${RED}✗ Models test failed${NC}"
        log_message "Models test: FAILED"
    fi
    
    # Specific model info
    echo "Testing Gemini Pro model info..."
    local gemini_pro_response=$(curl -s -H "Authorization: Bearer $access_token" \
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro" || echo '{"error": "failed"}')
    
    if echo "$gemini_pro_response" | jq -e '.inputTokenLimit' >/dev/null 2>&1; then
        local input_limit=$(echo "$gemini_pro_response" | jq -r '.inputTokenLimit')
        local output_limit=$(echo "$gemini_pro_response" | jq -r '.outputTokenLimit // "unknown"')
        echo -e "${GREEN}✓ Gemini Pro limits: Input=$input_limit, Output=$output_limit${NC}"
        log_message "Gemini Pro limits: $input_limit/$output_limit"
    else
        echo -e "${RED}✗ Gemini Pro info failed${NC}"
        log_message "Gemini Pro info: FAILED"
    fi
}

# Test usage-impacting endpoints (minimal usage)
test_usage_endpoints() {
    local access_token="$1"
    
    echo -e "\n${YELLOW}=== Testing Gemini Usage-Impacting Endpoints (Minimal) ===${NC}"
    echo -e "${YELLOW}WARNING: These tests will consume your daily quota${NC}"
    log_message "Starting usage-impacting endpoint tests"
    
    # Gemini Pro minimal test
    echo "Testing Gemini Pro text generation (1 token)..."
    local gemini_response=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        -d '{
            "contents": [
                {"parts": [{"text": "Hi"}]}
            ],
            "generationConfig": {
                "maxOutputTokens": 1
            }
        }' \
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent" || echo 'ERROR')
    
    local http_code=$(echo "$gemini_response" | grep "HTTP_CODE:" | cut -d: -f2)
    local response_body=$(echo "$gemini_response" | sed '/HTTP_CODE:/d')
    
    if [ "$http_code" == "200" ]; then
        local response_text=$(echo "$response_body" | jq -r '.candidates[0].content.parts[0].text // "No response"' 2>/dev/null)
        local usage_metadata=$(echo "$response_body" | jq -r '.usageMetadata // "No usage data"' 2>/dev/null)
        echo -e "${GREEN}✓ Gemini Pro test: SUCCESS${NC}"
        echo -e "${BLUE}Response: $response_text${NC}"
        echo -e "${BLUE}Usage: $usage_metadata${NC}"
        log_message "Gemini Pro test: SUCCESS - Response: $response_text"
    else
        echo -e "${RED}✗ Gemini Pro test failed (HTTP $http_code)${NC}"
        log_message "Gemini Pro test: FAILED (HTTP $http_code)"
        
        # Check for quota exceeded
        if [ "$http_code" == "429" ]; then
            echo -e "${YELLOW}Rate/quota limit exceeded${NC}"
        elif [ "$http_code" == "403" ]; then
            echo -e "${YELLOW}Access denied - check API permissions${NC}"
        fi
        
        # Try to parse error message
        local error_msg=$(echo "$response_body" | jq -r '.error.message // "No error details"' 2>/dev/null)
        echo -e "${RED}Error: $error_msg${NC}"
        log_message "Error message: $error_msg"
    fi
    
    # Test with safety settings
    echo "Testing with safety settings..."
    local safety_response=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        -d '{
            "contents": [
                {"parts": [{"text": "Hello world"}]}
            ],
            "generationConfig": {
                "maxOutputTokens": 5
            },
            "safetySettings": [
                {
                    "category": "HARM_CATEGORY_HARASSMENT",
                    "threshold": "BLOCK_MEDIUM_AND_ABOVE"
                }
            ]
        }' \
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent" || echo 'ERROR')
    
    local safety_http_code=$(echo "$safety_response" | grep "HTTP_CODE:" | cut -d: -f2)
    
    if [ "$safety_http_code" == "200" ]; then
        echo -e "${GREEN}✓ Safety settings test: SUCCESS${NC}"
        log_message "Safety settings test: SUCCESS"
    else
        echo -e "${RED}✗ Safety settings test failed (HTTP $safety_http_code)${NC}"
        log_message "Safety settings test: FAILED"
    fi
}

# Check quota status
check_quota_status() {
    local access_token="$1"
    
    echo -e "\n${BLUE}=== Checking Quota Status ===${NC}"
    log_message "Checking quota status"
    
    # Test a simple request and check for quota-related headers
    local quota_response=$(curl -s -I -H "Authorization: Bearer $access_token" \
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro" || echo 'failed')
    
    if [ "$quota_response" != "failed" ]; then
        # Look for quota headers (these may not exist for all accounts)
        local quota_remaining=$(echo "$quota_response" | grep -i "x-quota-remaining" | cut -d: -f2 | tr -d ' \r' || echo "unknown")
        local quota_limit=$(echo "$quota_response" | grep -i "x-quota-limit" | cut -d: -f2 | tr -d ' \r' || echo "unknown")
        
        if [ "$quota_remaining" != "unknown" ]; then
            echo -e "${BLUE}Quota remaining: $quota_remaining${NC}"
            echo -e "${BLUE}Quota limit: $quota_limit${NC}"
            log_message "Quota: $quota_remaining/$quota_limit"
        else
            echo -e "${YELLOW}Quota information not available in headers${NC}"
            log_message "No quota headers found"
        fi
        
        # Check response status
        if echo "$quota_response" | head -1 | grep -q "200"; then
            echo -e "${GREEN}API access: OK${NC}"
        else
            echo -e "${YELLOW}API access: Check response status${NC}"
        fi
    fi
    
    # Check token expiry
    local expiry_date=$(jq -r '.expiry_date // 0' "$CREDENTIALS_FILE" 2>/dev/null)
    local current_time=$(date +%s)
    
    if [ "$expiry_date" -gt 9999999999 ]; then
        expiry_date=$((expiry_date / 1000))
    fi
    
    local hours_until_expiry=$(( (expiry_date - current_time) / 3600 ))
    echo -e "${BLUE}Token expires in: $hours_until_expiry hours${NC}"
    log_message "Token expires in $hours_until_expiry hours"
}

# Monitor network activity
monitor_network() {
    echo -e "\n${BLUE}=== Network Activity Check ===${NC}"
    log_message "Checking network activity"
    
    # Check active connections
    local connections=$(netstat -tupln 2>/dev/null | grep "googleapis" || echo "")
    if [ -n "$connections" ]; then
        echo -e "${YELLOW}Active Google API connections:${NC}"
        echo "$connections"
        log_message "Active connections found"
    else
        echo -e "${GREEN}No active Google API connections${NC}"
        log_message "No active connections"
    fi
    
    # Check for Gemini-related processes
    local processes=$(ps aux | grep -E "(curl.*googleapis|gemini|google.*ai)" | grep -v grep || echo "")
    if [ -n "$processes" ]; then
        echo -e "${YELLOW}Gemini-related processes:${NC}"
        echo "$processes"
        log_message "Gemini processes detected"
    else
        echo -e "${GREEN}No Gemini processes detected${NC}"
        log_message "No Gemini processes"
    fi
}

# Main execution
main() {
    echo "Google Gemini API Test Script - $(date)"
    echo "========================================"
    
    local access_token
    access_token=$(get_access_token)
    
    # Run tests
    test_free_endpoints "$access_token"
    test_usage_endpoints "$access_token"
    check_quota_status "$access_token"
    monitor_network
    
    echo -e "\n${BLUE}Test completed. Log file: $LOG_FILE${NC}"
    echo -e "${YELLOW}Note: Usage tests consumed part of your daily quota${NC}"
    echo -e "${YELLOW}Free tier has daily limits - monitor your usage${NC}"
}

main "$@"