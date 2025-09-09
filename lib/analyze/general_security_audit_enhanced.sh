#!/bin/bash
# general_security_audit_enhanced.sh - Security audit with visual ceremonies and celebrations
# Created: 2025-09-06 by Claude (Anthropic AI Assistant)
# Purpose: Enhanced UX version using boxy ceremonies and jynx highlighting
#
# Usage: general_security_audit_enhanced.sh [--view=visual|data]
#   --view=visual (default) - Full visual output with boxy ceremonies and jynx coloring
#   --view=data - Plain text output for agents/automation (no colors, no boxes)

set -euo pipefail

# Parse command line arguments
VIEW_MODE="visual"
for arg in "$@"; do
    case $arg in
        --view=data)
            VIEW_MODE="data"
            ;;
        --view=visual)
            VIEW_MODE="visual"
            ;;
        --help|-h)
            echo "Usage: $0 [--view=visual|data]"
            echo "  --view=visual (default) - Full visual output with colors and boxes"
            echo "  --view=data - Plain text output for agents/automation"
            exit 0
            ;;
    esac
done

# Check for AGENT_MODE environment variable (future compatibility)
# Only suggest data mode, don't force it - agents can choose visual if they want
if [[ "${AGENT_MODE:-}" == "1" ]] || [[ "${AGENT_MODE:-}" == "true" ]]; then
    # If no explicit view mode was set, suggest data mode for agents
    if [[ ! "$@" =~ --view ]]; then
        echo "# Note: AGENT_MODE detected. Use --view=data for plain text or --view=visual for colors" >&2
        # Don't force it - let agent decide
    fi
fi

# Check for required tools
BOXY_PATH="/home/xnull/.local/bin/odx/boxy"
JYNX_PATH="/home/xnull/.local/bin/odx/jynx"
SECURITY_THEME="$(dirname "$(dirname "$(readlink -f "$0")")")/config/security-audit.yml"

# Fallback if tools not available
if [[ ! -x "$BOXY_PATH" ]] && [[ "$VIEW_MODE" == "visual" ]]; then
    echo "Warning: boxy not found, switching to data mode"
    VIEW_MODE="data"
fi

# Configuration
AUDIT_LOG="security_audit_$(date +%Y%m%d_%H%M%S).log"
RESULTS_DIR="security_audit_results_$(date +%Y%m%d_%H%M%S)"
SCORE_FILE="$RESULTS_DIR/security_score.txt"

# Security score tracking
TOTAL_CHECKS=0
PASSED_CHECKS=0
CRITICAL_ISSUES=0
HIGH_ISSUES=0
MEDIUM_ISSUES=0
LOW_ISSUES=0

# Test counter for ceremonies
TEST_NUMBER=0

# Create results directory
mkdir -p "$RESULTS_DIR"

# Helper function to apply jynx theme based on view mode
apply_theme() {
    if [[ "$VIEW_MODE" == "data" ]]; then
        # In data mode, strip all formatting
        if [[ -x "$JYNX_PATH" ]]; then
            $JYNX_PATH --no-color
        else
            cat
        fi
    elif [[ -x "$JYNX_PATH" ]] && [[ -f "$SECURITY_THEME" ]]; then
        # In visual mode, apply the security theme
        $JYNX_PATH -t "$SECURITY_THEME" -f security
    else
        cat
    fi
}

# Helper function to apply boxy based on view mode
apply_box() {
    local theme="$1"
    local title="$2"
    local border="${3:-rounded}"
    
    if [[ "$VIEW_MODE" == "data" ]]; then
        # In data mode, use --no-boxy to strip decoration
        if [[ -x "$BOXY_PATH" ]]; then
            $BOXY_PATH --no-boxy
        else
            cat
        fi
    elif [[ -x "$BOXY_PATH" ]]; then
        # In visual mode, apply boxy ceremony
        $BOXY_PATH --theme "$theme" --title "$title" --border "$border"
    else
        cat
    fi
}

# Helper functions for ceremonies
ceremony_pass() {
    local test_num="$1"
    local message="$2"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    
    if [[ "$VIEW_MODE" == "data" ]]; then
        echo "[PASS] TEST #$test_num: $message" | tee -a "$AUDIT_LOG"
    else
        echo "✅ TEST #$test_num PASSED: $message" | tee -a "$AUDIT_LOG" | \
            apply_theme | \
            apply_box "success" "Test #$test_num: PASSED" "rounded"
    fi
}

ceremony_fail() {
    local test_num="$1"
    local severity="$2"
    local message="$3"
    
    if [[ "$VIEW_MODE" == "data" ]]; then
        # Data mode: simple structured text
        case $severity in
            "CRITICAL")
                echo "[CRITICAL] TEST #$test_num: $message" | tee -a "$AUDIT_LOG"
                CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
                ;;
            "HIGH")
                echo "[HIGH] TEST #$test_num: $message" | tee -a "$AUDIT_LOG"
                HIGH_ISSUES=$((HIGH_ISSUES + 1))
                ;;
            "MEDIUM")
                echo "[MEDIUM] TEST #$test_num: $message" | tee -a "$AUDIT_LOG"
                MEDIUM_ISSUES=$((MEDIUM_ISSUES + 1))
                ;;
            "LOW")
                echo "[LOW] TEST #$test_num: $message" | tee -a "$AUDIT_LOG"
                LOW_ISSUES=$((LOW_ISSUES + 1))
                ;;
        esac
    else
        # Visual mode: full ceremonies with colors and boxes
        case $severity in
            "CRITICAL")
                echo "🚨 TEST #$test_num FAILED: CRITICAL: $message" | tee -a "$AUDIT_LOG" | \
                    apply_theme | \
                    apply_box "error" "Test #$test_num: CRITICAL FAILURE" "double"
                CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
                ;;
            "HIGH")
                echo "❌ TEST #$test_num FAILED: HIGH: $message" | tee -a "$AUDIT_LOG" | \
                    apply_theme | \
                    apply_box "error" "Test #$test_num: HIGH RISK" "heavy"
                HIGH_ISSUES=$((HIGH_ISSUES + 1))
                ;;
            "MEDIUM")
                echo "⚠️ TEST #$test_num WARNING: MEDIUM: $message" | tee -a "$AUDIT_LOG" | \
                    apply_theme | \
                    apply_box "warning" "Test #$test_num: MEDIUM RISK" "rounded"
                MEDIUM_ISSUES=$((MEDIUM_ISSUES + 1))
                ;;
            "LOW")
                echo "ℹ️ TEST #$test_num INFO: LOW: $message" | tee -a "$AUDIT_LOG" | \
                    apply_theme | \
                    apply_box "info" "Test #$test_num: LOW RISK" "normal"
                LOW_ISSUES=$((LOW_ISSUES + 1))
                ;;
        esac
    fi
}

next_test() {
    TEST_NUMBER=$((TEST_NUMBER + 1))
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
}

test_header() {
    local description="$1"
    if [[ "$VIEW_MODE" == "data" ]]; then
        echo "Checking Test #$TEST_NUMBER: $description..."
    else
        echo "Checking $description..." | $BOXY_PATH --theme info --title "Test #$TEST_NUMBER: $description"
    fi
}

# Header ceremony
if [[ "$VIEW_MODE" == "data" ]]; then
    echo "=== SYSTEM SECURITY AUDIT ==="
    echo "Date: $(date +%Y-%m-%d)"
    echo "Audit log: $AUDIT_LOG"
    echo "Results directory: $RESULTS_DIR"
    echo ""
    echo "=== System Information ==="
    uname -a | tee "$RESULTS_DIR/system_info.txt"
else
    echo "🛡️ SYSTEM SECURITY AUDIT" | \
        $BOXY_PATH --theme info --header "Security Assessment $(date +%Y-%m-%d)" --border double
    
    echo ""
    echo "Audit log: $AUDIT_LOG"
    echo "Results directory: $RESULTS_DIR"
    echo ""
    
    # System Information ceremony
    uname -a | tee "$RESULTS_DIR/system_info.txt" | \
        $BOXY_PATH --theme info --title "System Information" --border rounded
fi
echo ""

# =========================
# TEST CEREMONIES BEGIN
# =========================

# Test 1: Firewall Status
next_test
test_header "Firewall Configuration"

if command -v ufw >/dev/null 2>&1; then
    UFW_STATUS=$(ufw status | head -1)
    if echo "$UFW_STATUS" | grep -q "Status: active"; then
        ceremony_pass "$TEST_NUMBER" "UFW firewall is active and protecting the system"
        ufw status verbose > "$RESULTS_DIR/ufw_status.txt"
        
        # Sub-test for permissive rules
        next_test
        if ufw status | grep -q "Anywhere"; then
            ceremony_fail "$TEST_NUMBER" "MEDIUM" "UFW has rules allowing access from anywhere - review for necessity"
        else
            ceremony_pass "$TEST_NUMBER" "No overly permissive 'Anywhere' rules detected"
        fi
    else
        ceremony_fail "$TEST_NUMBER" "HIGH" "UFW firewall is NOT active - system is unprotected"
    fi
elif command -v iptables >/dev/null 2>&1; then
    IPTABLES_RULES=$(iptables -L 2>/dev/null | wc -l)
    if [ "$IPTABLES_RULES" -gt 10 ]; then
        ceremony_pass "$TEST_NUMBER" "iptables firewall rules are configured"
        iptables -L -n > "$RESULTS_DIR/iptables_rules.txt" 2>/dev/null
    else
        ceremony_fail "$TEST_NUMBER" "HIGH" "No firewall rules detected - iptables nearly empty"
    fi
else
    ceremony_fail "$TEST_NUMBER" "CRITICAL" "No firewall system detected (UFW/iptables missing)"
fi
echo ""

# Test 2: SSH Root Login
next_test
test_header "SSH Security"

if [ -f /etc/ssh/sshd_config ]; then
    SSH_CONFIG="/etc/ssh/sshd_config"
    
    if grep -q "^PermitRootLogin no" "$SSH_CONFIG"; then
        ceremony_pass "$TEST_NUMBER" "Root login via SSH is properly disabled"
    elif grep -q "^PermitRootLogin yes" "$SSH_CONFIG"; then
        ceremony_fail "$TEST_NUMBER" "CRITICAL" "Root login enabled via SSH - major security risk!"
    else
        ceremony_fail "$TEST_NUMBER" "HIGH" "Root login setting not explicitly configured"
    fi
    
    # Test 3: SSH Password Authentication
    next_test
    if grep -q "^PasswordAuthentication no" "$SSH_CONFIG"; then
        ceremony_pass "$TEST_NUMBER" "SSH password authentication disabled - using key-based auth"
    else
        ceremony_fail "$TEST_NUMBER" "MEDIUM" "SSH password authentication may be enabled - consider key-only"
    fi
    
    cp "$SSH_CONFIG" "$RESULTS_DIR/sshd_config.txt"
else
    ceremony_fail "$TEST_NUMBER" "LOW" "SSH daemon not installed or configured"
fi
echo ""

# Test 4: Users with Empty Passwords
next_test
test_header "User Account Security"

EMPTY_PASSWD_USERS=$(awk -F: '($2 == "") {print $1}' /etc/shadow 2>/dev/null | wc -l)
if [ "$EMPTY_PASSWD_USERS" -eq 0 ]; then
    ceremony_pass "$TEST_NUMBER" "No users have empty passwords"
else
    ceremony_fail "$TEST_NUMBER" "CRITICAL" "$EMPTY_PASSWD_USERS user(s) have empty passwords!"
fi

# Test 5: Non-root users with UID 0
next_test
ROOT_USERS=$(awk -F: '($3 == 0) {print $1}' /etc/passwd | grep -v "^root$" | wc -l)
if [ "$ROOT_USERS" -eq 0 ]; then
    ceremony_pass "$TEST_NUMBER" "Only root user has UID 0 (proper privilege separation)"
else
    ceremony_fail "$TEST_NUMBER" "CRITICAL" "$ROOT_USERS non-root user(s) have UID 0 privileges!"
fi
echo ""

# Test 6: Critical File Permissions
next_test
test_header "File Permissions"

PASSWD_PERMS=$(stat -c %a /etc/passwd)
if [ "$PASSWD_PERMS" = "644" ]; then
    ceremony_pass "$TEST_NUMBER" "/etc/passwd has correct permissions (644)"
else
    ceremony_fail "$TEST_NUMBER" "MEDIUM" "/etc/passwd has incorrect permissions ($PASSWD_PERMS, should be 644)"
fi

# Test 7: Shadow File Permissions
next_test
SHADOW_PERMS=$(stat -c %a /etc/shadow 2>/dev/null || echo "000")
if [ "$SHADOW_PERMS" = "640" ] || [ "$SHADOW_PERMS" = "600" ]; then
    ceremony_pass "$TEST_NUMBER" "/etc/shadow has secure permissions ($SHADOW_PERMS)"
else
    ceremony_fail "$TEST_NUMBER" "HIGH" "/etc/shadow has incorrect permissions ($SHADOW_PERMS)"
fi

# Test 8: World-writable Files
next_test
WORLD_WRITABLE=$(find /etc /bin /sbin /usr/bin /usr/sbin -type f -perm -002 2>/dev/null | wc -l)
if [ "$WORLD_WRITABLE" -eq 0 ]; then
    ceremony_pass "$TEST_NUMBER" "No world-writable files in system directories"
else
    ceremony_fail "$TEST_NUMBER" "HIGH" "$WORLD_WRITABLE world-writable file(s) found in system directories"
    find /etc /bin /sbin /usr/bin /usr/sbin -type f -perm -002 2>/dev/null > "$RESULTS_DIR/world_writable_files.txt"
fi
echo ""

# Test 9: Dangerous Network Services
next_test
test_header "Network Services"

LISTENING_SERVICES=$(netstat -tlnp 2>/dev/null | grep LISTEN | wc -l)
netstat -tlnp 2>/dev/null | grep LISTEN > "$RESULTS_DIR/listening_services.txt"

DANGEROUS_PORTS="21 23 135 445 1433 3306 5432"
DANGEROUS_FOUND=0
for port in $DANGEROUS_PORTS; do
    if netstat -tln 2>/dev/null | grep ":$port " >/dev/null; then
        DANGEROUS_FOUND=$((DANGEROUS_FOUND + 1))
    fi
done

if [ "$DANGEROUS_FOUND" -eq 0 ]; then
    ceremony_pass "$TEST_NUMBER" "No dangerous services detected on common attack ports"
else
    ceremony_fail "$TEST_NUMBER" "HIGH" "$DANGEROUS_FOUND dangerous service(s) detected on risky ports"
fi
echo ""

# Test 10: Package Updates
next_test
test_header "Package Management"

if command -v apt >/dev/null 2>&1; then
    UPDATES=$(apt list --upgradable 2>/dev/null | grep -c upgradable || echo "0")
    if [ "$UPDATES" -eq 0 ]; then
        ceremony_pass "$TEST_NUMBER" "All system packages are up to date"
    else
        SECURITY_UPDATES=$(apt list --upgradable 2>/dev/null | grep -i security | wc -l || echo "0")
        if [ "$SECURITY_UPDATES" -gt 0 ]; then
            ceremony_fail "$TEST_NUMBER" "HIGH" "$SECURITY_UPDATES security update(s) available!"
        else
            ceremony_fail "$TEST_NUMBER" "MEDIUM" "$UPDATES package update(s) available"
        fi
        apt list --upgradable 2>/dev/null > "$RESULTS_DIR/available_updates.txt"
    fi
elif command -v apk >/dev/null 2>&1; then
    ceremony_pass "$TEST_NUMBER" "Alpine Linux package manager detected"
    apk list -u > "$RESULTS_DIR/apk_upgradable.txt" 2>/dev/null
fi
echo ""

# Test 11: AI CLI Security
next_test
test_header "AI CLI Security"

AI_CLIS_FOUND=0
for cli in codex gemini claude; do
    if command -v "$cli" >/dev/null 2>&1; then
        AI_CLIS_FOUND=$((AI_CLIS_FOUND + 1))
        which "$cli" >> "$RESULTS_DIR/ai_cli_locations.txt"
    fi
done

if [ "$AI_CLIS_FOUND" -eq 0 ]; then
    ceremony_pass "$TEST_NUMBER" "No AI CLI tools detected"
else
    ceremony_fail "$TEST_NUMBER" "MEDIUM" "$AI_CLIS_FOUND AI CLI tool(s) detected - review with AI security tools"
fi

# Test 12: Ollama Detection
next_test
if pgrep -f "ollama" >/dev/null || command -v ollama >/dev/null 2>&1; then
    ceremony_fail "$TEST_NUMBER" "HIGH" "Ollama local AI detected - significant resource/security risk"
    echo "Ollama status: ACTIVE" >> "$RESULTS_DIR/ai_cli_status.txt"
else
    ceremony_pass "$TEST_NUMBER" "Ollama local AI not detected"
fi
echo ""

# =========================
# FINAL CELEBRATION
# =========================

# Calculate Security Score
SCORE=10
SCORE=$((SCORE - (CRITICAL_ISSUES * 2)))
SCORE=$((SCORE - HIGH_ISSUES))
SCORE=$((SCORE - (MEDIUM_ISSUES / 2)))
SCORE=$((SCORE - (LOW_ISSUES / 10)))

if [ "$SCORE" -lt 0 ]; then
    SCORE=0
fi

# Determine rating and theme
if [ "$SCORE" -ge 9 ]; then
    RATING="EXCELLENT"
    CELEBRATION_THEME="success"
    EMOJI="🏆"
elif [ "$SCORE" -ge 7 ]; then
    RATING="GOOD"
    CELEBRATION_THEME="success"
    EMOJI="✅"
elif [ "$SCORE" -ge 5 ]; then
    RATING="FAIR"
    CELEBRATION_THEME="warning"
    EMOJI="⚠️"
elif [ "$SCORE" -ge 3 ]; then
    RATING="POOR"
    CELEBRATION_THEME="error"
    EMOJI="❌"
else
    RATING="CRITICAL"
    CELEBRATION_THEME="error"
    EMOJI="🚨"
fi

# Create detailed score file
cat > "$SCORE_FILE" << EOF
Security Audit Score: $SCORE/10 ($RATING)
Generated: $(date)

TEST RESULTS:
Total Tests: $TOTAL_CHECKS
Passed: $PASSED_CHECKS
Failed: $(( CRITICAL_ISSUES + HIGH_ISSUES + MEDIUM_ISSUES + LOW_ISSUES ))

ISSUE BREAKDOWN:
Critical Issues: $CRITICAL_ISSUES
High Issues: $HIGH_ISSUES
Medium Issues: $MEDIUM_ISSUES
Low Issues: $LOW_ISSUES

Pass Rate: $(( (PASSED_CHECKS * 100) / TOTAL_CHECKS ))%
EOF

# Final Celebration Box
echo ""
if [[ "$VIEW_MODE" == "data" ]]; then
    # Data mode: structured text output
    echo "=== AUDIT COMPLETE ==="
    echo "Final Score: $SCORE/10 ($RATING)"
    echo "Tests Passed: $PASSED_CHECKS/$TOTAL_CHECKS"
    echo "Critical Issues: $CRITICAL_ISSUES"
    echo "High Risk Issues: $HIGH_ISSUES"
    echo "Medium Risk Issues: $MEDIUM_ISSUES"
    echo "Low Risk Issues: $LOW_ISSUES"
    echo "Pass Rate: $(( (PASSED_CHECKS * 100) / TOTAL_CHECKS ))%"
    echo "Results saved to: $RESULTS_DIR"
else
    # Visual mode: celebration ceremony
    {
        echo "$EMOJI SECURITY AUDIT CELEBRATION $EMOJI"
        echo ""
        echo "Final Score: $SCORE/10 ($RATING)"
        echo ""
        echo "Tests Passed: $PASSED_CHECKS/$TOTAL_CHECKS"
        echo "Critical Issues: $CRITICAL_ISSUES"
        echo "High Risk Issues: $HIGH_ISSUES"
        echo "Medium Risk Issues: $MEDIUM_ISSUES"
        echo "Low Risk Issues: $LOW_ISSUES"
        echo ""
        echo "Pass Rate: $(( (PASSED_CHECKS * 100) / TOTAL_CHECKS ))%"
        echo ""
        echo "Results saved to: $RESULTS_DIR"
    } | apply_theme | apply_box "$CELEBRATION_THEME" "🎉 AUDIT COMPLETE 🎉" "double"
fi

echo ""

# Generate recommendations file
cat > "$RESULTS_DIR/security_recommendations.txt" << EOF
SECURITY HARDENING RECOMMENDATIONS
Generated: $(date)
Current Score: $SCORE/10 ($RATING)

=== IMMEDIATE ACTIONS (Critical/High Issues) ===
$(grep "CRITICAL\|HIGH" "$AUDIT_LOG" | sed 's/.*: /• /')

=== SUGGESTED IMPROVEMENTS ===
$(grep "MEDIUM" "$AUDIT_LOG" | sed 's/.*: /• /')

=== HARDENING COMMANDS ===
# Enable firewall
sudo ufw enable
sudo ufw default deny incoming

# Secure SSH
sudo sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# Update packages
sudo apt update && sudo apt upgrade -y

# AI CLI security (if applicable)
~/repos/security/bin/detect_ollama.sh
~/repos/security/bin/block_telemetry.sh
EOF

# Show key files with jynx highlighting if available
if [[ -x "$JYNX_PATH" ]]; then
    echo "Key output files:" | $JYNX_PATH
    echo "  - $SCORE_FILE"
    echo "  - $RESULTS_DIR/security_recommendations.txt"
    echo "  - $AUDIT_LOG"
else
    echo "Key output files:"
    echo "  - $SCORE_FILE"
    echo "  - $RESULTS_DIR/security_recommendations.txt"  
    echo "  - $AUDIT_LOG"
fi

# Return appropriate exit code
if [ "$CRITICAL_ISSUES" -gt 0 ]; then
    exit 2
elif [ "$HIGH_ISSUES" -gt 0 ]; then
    exit 1
else
    exit 0
fi