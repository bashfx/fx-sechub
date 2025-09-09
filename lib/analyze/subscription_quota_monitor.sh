#!/bin/bash
# Subscription Quota Monitor
# Tracks usage against subscription limits for DoS attack detection

set -euo pipefail

# Configuration
QUOTA_LOG="$HOME/quota_monitoring_$(date +%Y%m%d).log"
ALERT_THRESHOLD=80  # Alert at 80% quota usage

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_message() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$QUOTA_LOG"
}

alert() {
    echo -e "${RED}QUOTA ALERT: $1${NC}" | tee -a "$QUOTA_LOG"
}

warning() {
    echo -e "${YELLOW}QUOTA WARNING: $1${NC}" | tee -a "$QUOTA_LOG"
}

# Check OpenAI subscription quota usage
check_openai_subscription() {
    log_message "=== OpenAI Subscription Quota Check ==="
    
    local api_key=""
    if [ -f ~/.codex/auth.json ]; then
        api_key=$(jq -r '.OPENAI_API_KEY // empty' ~/.codex/auth.json 2>/dev/null)
    fi
    
    if [ -z "$api_key" ] || [ "$api_key" == "null" ]; then
        log_message "No OpenAI API key found"
        return 0
    fi
    
    # Check usage statistics (conceptual - API endpoints vary)
    local usage_response=$(curl -s -H "Authorization: Bearer $api_key" \
        "https://api.openai.com/v1/usage?date=$(date +%Y-%m-%d)" 2>/dev/null || echo '{"error": "failed"}')
    
    if ! echo "$usage_response" | jq -e '.error' >/dev/null 2>&1; then
        log_message "OpenAI usage data retrieved"
        
        # Analyze usage patterns for subscription abuse
        # Look for rapid consumption of daily/monthly limits
        
        # Check for high-frequency requests (DoS indicator)
        local request_count=$(echo "$usage_response" | jq '.total_requests // 0' 2>/dev/null || echo "0")
        if [ "$request_count" -gt 100 ]; then
            warning "High request volume today: $request_count requests"
        fi
        
        # Check for expensive model usage
        local gpt4_usage=$(echo "$usage_response" | jq '.gpt4_requests // 0' 2>/dev/null || echo "0")
        if [ "$gpt4_usage" -gt 20 ]; then
            warning "High GPT-4 usage: $gpt4_usage requests"
        fi
        
    else
        log_message "Could not retrieve OpenAI usage statistics"
    fi
    
    # Check current rate limit status by testing API response headers
    log_message "Testing OpenAI rate limit status..."
    local rate_limit_test=$(curl -s -I -H "Authorization: Bearer $api_key" \
        "https://api.openai.com/v1/models" 2>/dev/null || echo "failed")
    
    if [ "$rate_limit_test" != "failed" ]; then
        # Extract rate limit headers if available
        local remaining=$(echo "$rate_limit_test" | grep -i "x-ratelimit-remaining" | cut -d: -f2 | tr -d ' \r' || echo "unknown")
        local limit=$(echo "$rate_limit_test" | grep -i "x-ratelimit-limit" | cut -d: -f2 | tr -d ' \r' || echo "unknown")
        
        if [ "$remaining" != "unknown" ] && [ "$limit" != "unknown" ]; then
            local usage_percent=$(( (limit - remaining) * 100 / limit ))
            echo -e "${BLUE}Rate limit usage: ${usage_percent}% (${remaining}/${limit})${NC}"
            
            if [ "$usage_percent" -gt "$ALERT_THRESHOLD" ]; then
                alert "OpenAI rate limit nearly exhausted: ${usage_percent}%"
            fi
        fi
    fi
}

# Check Gemini subscription quota
check_gemini_subscription() {
    log_message "=== Gemini Subscription Quota Check ==="
    
    local access_token=""
    if [ -f ~/.gemini/oauth_creds.json ]; then
        access_token=$(jq -r '.access_token // empty' ~/.gemini/oauth_creds.json 2>/dev/null)
    fi
    
    if [ -z "$access_token" ] || [ "$access_token" == "null" ]; then
        log_message "No Gemini access token found"
        return 0
    fi
    
    # Check quota status through models endpoint
    local models_response=$(curl -s -I -H "Authorization: Bearer $access_token" \
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro" 2>/dev/null || echo "failed")
    
    if [ "$models_response" != "failed" ]; then
        # Look for quota-related headers
        local quota_remaining=$(echo "$models_response" | grep -i "x-quota-remaining" | cut -d: -f2 | tr -d ' \r' || echo "unknown")
        
        if [ "$quota_remaining" != "unknown" ]; then
            echo -e "${BLUE}Gemini quota remaining: $quota_remaining${NC}"
            log_message "Gemini quota remaining: $quota_remaining"
            
            # Alert if quota is running low (this is conceptual)
            if [ "$quota_remaining" -lt 1000 ]; then
                alert "Gemini quota running low: $quota_remaining remaining"
            fi
        fi
        
        # Check for rate limit indicators
        if echo "$models_response" | grep -q "429\|quota"; then
            alert "Gemini quota/rate limit issues detected"
        fi
    fi
}

# Check Claude subscription status
check_claude_subscription() {
    log_message "=== Claude Subscription Quota Check ==="
    
    if [ ! -f ~/.claude/.credentials.json ]; then
        log_message "No Claude credentials found"
        return 0
    fi
    
    # Check subscription type and status
    local subscription=$(jq -r '.claudeAiOauth.subscriptionType // "unknown"' ~/.claude/.credentials.json 2>/dev/null)
    local expires_at=$(jq -r '.claudeAiOauth.expiresAt // 0' ~/.claude/.credentials.json 2>/dev/null)
    
    echo -e "${BLUE}Claude subscription: $subscription${NC}"
    log_message "Claude subscription type: $subscription"
    
    # Calculate token expiry
    if [ "$expires_at" -gt 0 ]; then
        local current_time=$(date +%s)
        if [ "$expires_at" -gt 9999999999 ]; then
            expires_at=$((expires_at / 1000))
        fi
        
        local hours_until_expiry=$(( (expires_at - current_time) / 3600 ))
        
        if [ "$hours_until_expiry" -lt 24 ]; then
            warning "Claude token expires soon: $hours_until_expiry hours"
        fi
        
        echo -e "${BLUE}Token expires in: $hours_until_expiry hours${NC}"
    fi
    
    # Test API access to check for quota issues
    local access_token=$(jq -r '.claudeAiOauth.accessToken // empty' ~/.claude/.credentials.json 2>/dev/null)
    
    if [ -n "$access_token" ] && [ "$access_token" != "null" ]; then
        local test_response=$(curl -s -I -H "Authorization: Bearer $access_token" \
            -H "anthropic-version: 2023-06-01" \
            "https://api.anthropic.com/v1/models" 2>/dev/null || echo "failed")
        
        if [ "$test_response" != "failed" ]; then
            if echo "$test_response" | grep -q "429\|quota\|limit"; then
                alert "Claude quota/rate limit issues detected"
            elif echo "$test_response" | grep -q "200"; then
                echo -e "${GREEN}Claude API access: OK${NC}"
            fi
        fi
    fi
}

# Monitor for quota abuse patterns
check_abuse_patterns() {
    log_message "=== Quota Abuse Pattern Detection ==="
    
    # Check for rapid API consumption patterns
    local current_hour=$(date +%H)
    local api_processes=$(ps aux | grep -E "(curl.*api\.|python.*openai|gemini|claude)" | grep -v grep | wc -l)
    
    if [ "$api_processes" -gt 5 ]; then
        alert "High number of API processes detected: $api_processes"
    fi
    
    # Check for off-hours usage (subscription abuse often happens outside business hours)
    if [ "$current_hour" -ge 22 ] || [ "$current_hour" -le 6 ]; then
        if [ "$api_processes" -gt 0 ]; then
            warning "API activity detected during off-hours: $api_processes processes"
        fi
    fi
    
    # Check system resource usage (high usage might indicate rapid API calls)
    local memory_usage=$(free | awk '/Mem/ {printf "%.0f", $3/$2 * 100}' 2>/dev/null || echo "0")
    if [ "$memory_usage" -gt 80 ]; then
        warning "High memory usage: ${memory_usage}% (possible quota abuse)"
    fi
    
    # Check for network connection patterns
    local api_connections=$(netstat -tupln 2>/dev/null | grep -E "(openai|anthropic|googleapis)" | wc -l)
    if [ "$api_connections" -gt 10 ]; then
        alert "Unusually high number of API connections: $api_connections"
    fi
}

# Check subscription billing status
check_billing_status() {
    log_message "=== Subscription Billing Status ==="
    
    # Remind user to check billing dashboards
    echo -e "${YELLOW}Manual checks recommended:${NC}"
    echo "- OpenAI: https://platform.openai.com/usage"
    echo "- Google: https://console.cloud.google.com/billing"  
    echo "- Anthropic: Check Claude account settings"
    
    log_message "Billing dashboard checks recommended"
    
    # Check for any billing-related files or processes
    local billing_files=$(find ~ -name "*billing*" -o -name "*invoice*" -o -name "*payment*" 2>/dev/null | head -5 || true)
    if [ -n "$billing_files" ]; then
        log_message "Found billing-related files (check for anomalies):"
        echo "$billing_files" | while read file; do
            log_message "  - $file"
        done
    fi
}

# Generate quota usage report
generate_quota_report() {
    log_message "=== Quota Usage Summary ==="
    
    local timestamp=$(date)
    local report_file="$HOME/quota_report_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" << EOF
Subscription Quota Report
Generated: $timestamp

=== SUBSCRIPTION STATUS ===
EOF
    
    # Add OpenAI status
    if [ -f ~/.codex/auth.json ]; then
        echo "OpenAI: API key configured" >> "$report_file"
    else
        echo "OpenAI: No API key found" >> "$report_file"
    fi
    
    # Add Gemini status  
    if [ -f ~/.gemini/oauth_creds.json ]; then
        echo "Gemini: OAuth configured" >> "$report_file"
    else
        echo "Gemini: No OAuth found" >> "$report_file"
    fi
    
    # Add Claude status
    if [ -f ~/.claude/.credentials.json ]; then
        local subscription=$(jq -r '.claudeAiOauth.subscriptionType // "unknown"' ~/.claude/.credentials.json 2>/dev/null)
        echo "Claude: $subscription subscription" >> "$report_file"
    else
        echo "Claude: No credentials found" >> "$report_file"
    fi
    
    echo "" >> "$report_file"
    echo "=== RECOMMENDATIONS ===" >> "$report_file"
    echo "1. Monitor usage dashboards daily" >> "$report_file"
    echo "2. Set up billing alerts if available" >> "$report_file"  
    echo "3. Review API activity logs regularly" >> "$report_file"
    echo "4. Rotate authentication tokens monthly" >> "$report_file"
    
    echo -e "${BLUE}Quota report saved: $report_file${NC}"
    log_message "Generated quota report: $report_file"
}

# Main execution
main() {
    echo "Subscription Quota Monitor - $(date)"
    echo "==========================================="
    
    check_openai_subscription
    echo ""
    check_gemini_subscription  
    echo ""
    check_claude_subscription
    echo ""
    check_abuse_patterns
    echo ""
    check_billing_status
    echo ""
    generate_quota_report
    
    echo ""
    echo -e "${BLUE}Monitoring completed. Log: $QUOTA_LOG${NC}"
    
    # Check if any alerts were generated
    if grep -q "ALERT\|WARNING" "$QUOTA_LOG" 2>/dev/null; then
        echo -e "${RED}⚠️  ALERTS DETECTED - Review log file${NC}"
        return 1
    else
        echo -e "${GREEN}✓ No quota issues detected${NC}"
        return 0
    fi
}

main "$@"