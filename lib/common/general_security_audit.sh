#!/bin/bash
# general_security_audit.sh - Comprehensive system security assessment
# Created: 2025-09-06 by Claude (Anthropic AI Assistant)
# Purpose: System-wide security audit with hardening recommendations

set -euo pipefail

# Configuration - Iron Gate Path Resolution
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
AUDIT_LOG="security_audit_${TIMESTAMP}.log"
# Ensure absolute path resolution from script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Resolve absolute path to datahold directory
DATAHOLD_DIR="/home/xnull/repos/security/datahold"
if [ ! -d "$DATAHOLD_DIR" ]; then
    # Fallback to relative path if absolute doesn't exist
    DATAHOLD_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/datahold"
fi
RESULTS_DIR="$DATAHOLD_DIR/security_audit_results_${TIMESTAMP}"
SCORE_FILE="$RESULTS_DIR/security_score.txt"

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Security score tracking
TOTAL_CHECKS=0
PASSED_CHECKS=0
CRITICAL_ISSUES=0
HIGH_ISSUES=0
MEDIUM_ISSUES=0
LOW_ISSUES=0

# Iron Gate Directory Creation - Ensure absolute path exists
ensure_results_dir() {
    if [ ! -d "$RESULTS_DIR" ]; then
        mkdir -p "$RESULTS_DIR" || {
            echo "FATAL: Cannot create results directory: $RESULTS_DIR" >&2
            exit 1
        }
    fi
    # Fix ownership if running under sudo
    if [ -n "${SUDO_USER:-}" ]; then
        chown "$SUDO_USER:$SUDO_USER" "$RESULTS_DIR"
    fi
}

# Create results directory with ownership handling
ensure_results_dir

# Logging functions with directory validation
log_message() {
    ensure_results_dir  # Ensure directory exists before any file operations
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$AUDIT_LOG"
}

security_pass() {
    ensure_results_dir  # Iron Gate protection
    echo -e "${GREEN}✓ PASS: $1${NC}" | tee -a "$AUDIT_LOG"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
}

security_fail() {
    local severity="$1"
    local message="$2"
    
    ensure_results_dir  # Iron Gate protection
    
    case $severity in
        "CRITICAL")
            echo -e "${RED}✗ CRITICAL: $message${NC}" | tee -a "$AUDIT_LOG"
            CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
            ;;
        "HIGH")
            echo -e "${RED}✗ HIGH: $message${NC}" | tee -a "$AUDIT_LOG"
            HIGH_ISSUES=$((HIGH_ISSUES + 1))
            ;;
        "MEDIUM")
            echo -e "${YELLOW}⚠ MEDIUM: $message${NC}" | tee -a "$AUDIT_LOG"
            MEDIUM_ISSUES=$((MEDIUM_ISSUES + 1))
            ;;
        "LOW")
            echo -e "${BLUE}ⓘ LOW: $message${NC}" | tee -a "$AUDIT_LOG"
            LOW_ISSUES=$((LOW_ISSUES + 1))
            ;;
    esac
}

check_increment() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
}

# Iron Gate file ownership correction
fix_file_ownership() {
    local file_path="$1"
    if [ -n "${SUDO_USER:-}" ] && [ -f "$file_path" ]; then
        chown "$SUDO_USER:$SUDO_USER" "$file_path" 2>/dev/null || true
    fi
}

echo "=== System Security Audit ==="
echo "Audit log: $AUDIT_LOG"
echo "Results directory: $RESULTS_DIR"
echo ""

# System Information
log_message "=== System Information ==="
uname -a | tee "$RESULTS_DIR/system_info.txt"
fix_file_ownership "$RESULTS_DIR/system_info.txt"
lsb_release -a 2>/dev/null | tee -a "$RESULTS_DIR/system_info.txt" || echo "LSB info not available"
fix_file_ownership "$RESULTS_DIR/system_info.txt"

# 1. Firewall Configuration Audit
log_message "=== Firewall Configuration Audit ==="

check_increment
if command -v ufw >/dev/null 2>&1; then
    UFW_STATUS=$(ufw status | head -1)
    if echo "$UFW_STATUS" | grep -q "Status: active"; then
        security_pass "UFW firewall is active"
        ufw status verbose > "$RESULTS_DIR/ufw_status.txt"
        fix_file_ownership "$RESULTS_DIR/ufw_status.txt"
        
        # Check for overly permissive rules
        if ufw status | grep -q "Anywhere"; then
            security_fail "MEDIUM" "UFW has rules allowing access from anywhere"
        fi
    else
        security_fail "HIGH" "UFW firewall is not active"
    fi
else
    # Check iptables if UFW not available
    if command -v iptables >/dev/null 2>&1; then
        IPTABLES_RULES=$(iptables -L | wc -l)
        if [ "$IPTABLES_RULES" -gt 10 ]; then
            security_pass "iptables rules configured"
            iptables -L -n > "$RESULTS_DIR/iptables_rules.txt"
            fix_file_ownership "$RESULTS_DIR/iptables_rules.txt"
        else
            security_fail "HIGH" "No firewall rules detected (iptables nearly empty)"
        fi
    else
        security_fail "CRITICAL" "No firewall system detected (UFW/iptables missing)"
    fi
fi

# 2. SSH Configuration Audit  
log_message "=== SSH Configuration Audit ==="

check_increment
if [ -f /etc/ssh/sshd_config ]; then
    security_pass "SSH daemon configuration found"
    
    # Check critical SSH settings
    SSH_CONFIG="/etc/ssh/sshd_config"
    
    check_increment
    if grep -q "^PermitRootLogin no" "$SSH_CONFIG"; then
        security_pass "Root login disabled via SSH"
    elif grep -q "^PermitRootLogin yes" "$SSH_CONFIG"; then
        security_fail "CRITICAL" "Root login enabled via SSH"
    else
        security_fail "HIGH" "Root login setting not explicitly configured"
    fi
    
    check_increment
    if grep -q "^PasswordAuthentication no" "$SSH_CONFIG"; then
        security_pass "SSH password authentication disabled"
    else
        security_fail "MEDIUM" "SSH password authentication may be enabled"
    fi
    
    check_increment
    if grep -q "^Protocol 2" "$SSH_CONFIG"; then
        security_pass "SSH Protocol 2 specified"
    else
        security_fail "LOW" "SSH protocol version not explicitly set to 2"
    fi
    
    # Copy SSH config for analysis
    cp "$SSH_CONFIG" "$RESULTS_DIR/sshd_config.txt"
    fix_file_ownership "$RESULTS_DIR/sshd_config.txt"
else
    security_fail "LOW" "SSH daemon not installed or configured"
fi

# 3. User Account Security
log_message "=== User Account Security ==="

check_increment
# Check for users with empty passwords
EMPTY_PASSWD_USERS=$(awk -F: '($2 == "") {print $1}' /etc/shadow 2>/dev/null | wc -l)
if [ "$EMPTY_PASSWD_USERS" -eq 0 ]; then
    security_pass "No users with empty passwords"
else
    security_fail "CRITICAL" "$EMPTY_PASSWD_USERS users have empty passwords"
fi

check_increment
# Check for users with UID 0 (root privileges)
ROOT_USERS=$(awk -F: '($3 == 0) {print $1}' /etc/passwd | grep -v "^root$" | wc -l)
if [ "$ROOT_USERS" -eq 0 ]; then
    security_pass "Only root has UID 0"
else
    security_fail "CRITICAL" "$ROOT_USERS non-root users have UID 0"
fi

# Generate user analysis
ensure_results_dir  # Iron Gate protection for critical line 201
awk -F: '{print $1 ":" $3 ":" $6}' /etc/passwd | sort -t: -k2 -n > "$RESULTS_DIR/user_accounts.txt"
fix_file_ownership "$RESULTS_DIR/user_accounts.txt"

# 4. File Permissions Audit
log_message "=== File Permissions Audit ==="

check_increment
# Check /etc/passwd permissions
PASSWD_PERMS=$(stat -c %a /etc/passwd)
if [ "$PASSWD_PERMS" = "644" ]; then
    security_pass "/etc/passwd has correct permissions (644)"
else
    security_fail "MEDIUM" "/etc/passwd has incorrect permissions ($PASSWD_PERMS, should be 644)"
fi

check_increment  
# Check /etc/shadow permissions
SHADOW_PERMS=$(stat -c %a /etc/shadow 2>/dev/null || echo "000")
if [ "$SHADOW_PERMS" = "640" ] || [ "$SHADOW_PERMS" = "600" ]; then
    security_pass "/etc/shadow has secure permissions ($SHADOW_PERMS)"
else
    security_fail "HIGH" "/etc/shadow has incorrect permissions ($SHADOW_PERMS)"
fi

check_increment
# Check for world-writable files in system directories
WORLD_WRITABLE=$(find /etc /bin /sbin /usr/bin /usr/sbin -type f -perm -002 2>/dev/null | wc -l)
if [ "$WORLD_WRITABLE" -eq 0 ]; then
    security_pass "No world-writable files in system directories"
else
    security_fail "HIGH" "$WORLD_WRITABLE world-writable files in system directories"
    find /etc /bin /sbin /usr/bin /usr/sbin -type f -perm -002 2>/dev/null > "$RESULTS_DIR/world_writable_files.txt"
    fix_file_ownership "$RESULTS_DIR/world_writable_files.txt"
fi

# 5. Network Services Audit
log_message "=== Network Services Audit ==="

check_increment
# Check for unnecessary services listening
LISTENING_SERVICES=$(netstat -tlnp 2>/dev/null | grep LISTEN | wc -l)
log_message "Found $LISTENING_SERVICES listening services"
netstat -tlnp 2>/dev/null | grep LISTEN > "$RESULTS_DIR/listening_services.txt"
fix_file_ownership "$RESULTS_DIR/listening_services.txt"

# Check for dangerous services
DANGEROUS_PORTS="21 23 135 445 1433 3306 5432"
for port in $DANGEROUS_PORTS; do
    check_increment
    if netstat -tln 2>/dev/null | grep ":$port " >/dev/null; then
        security_fail "HIGH" "Potentially dangerous service on port $port"
    else
        security_pass "Port $port not listening"
    fi
done

# 6. Package Management Security
log_message "=== Package Management Security ==="

check_increment
if command -v apt >/dev/null 2>&1; then
    # Check for available updates
    UPDATES=$(apt list --upgradable 2>/dev/null | grep -c upgradable || echo "0")
    if [ "$UPDATES" -eq 0 ]; then
        security_pass "System packages are up to date"
    else
        security_fail "MEDIUM" "$UPDATES packages need updates"
        apt list --upgradable 2>/dev/null > "$RESULTS_DIR/available_updates.txt"
        fix_file_ownership "$RESULTS_DIR/available_updates.txt"
    fi
    
    # Check for security updates specifically
    SECURITY_UPDATES=$(apt list --upgradable 2>/dev/null | grep -i security | wc -l || echo "0")
    if [ "$SECURITY_UPDATES" -gt 0 ]; then
        security_fail "HIGH" "$SECURITY_UPDATES security updates available"
    fi
elif command -v apk >/dev/null 2>&1; then
    # Alpine Linux package management
    security_pass "Alpine Linux package manager detected"
    apk list -u > "$RESULTS_DIR/apk_upgradable.txt" 2>/dev/null
    fix_file_ownership "$RESULTS_DIR/apk_upgradable.txt"
fi

# 7. Kernel Security
log_message "=== Kernel Security ==="

check_increment
# Check kernel version for known vulnerabilities
KERNEL_VERSION=$(uname -r)
log_message "Kernel version: $KERNEL_VERSION"
echo "Kernel: $KERNEL_VERSION" > "$RESULTS_DIR/kernel_info.txt"
fix_file_ownership "$RESULTS_DIR/kernel_info.txt"

# Check if kernel is relatively recent (within 2 years is reasonable)
KERNEL_DATE=$(stat -c %Y /boot/vmlinuz-* 2>/dev/null | sort -n | tail -1)
CURRENT_DATE=$(date +%s)
AGE_DAYS=$(( (CURRENT_DATE - KERNEL_DATE) / 86400 ))

if [ "$AGE_DAYS" -lt 730 ]; then  # 2 years
    security_pass "Kernel is relatively recent ($AGE_DAYS days old)"
else
    security_fail "MEDIUM" "Kernel is quite old ($AGE_DAYS days old)"
fi

# 8. Log Security
log_message "=== Log Security ==="

check_increment
if [ -d /var/log ]; then
    security_pass "System log directory exists"
    
    # Check log directory permissions
    LOG_PERMS=$(stat -c %a /var/log)
    if [ "$LOG_PERMS" = "755" ] || [ "$LOG_PERMS" = "750" ]; then
        security_pass "Log directory has appropriate permissions"
    else
        security_fail "MEDIUM" "Log directory permissions may be too permissive ($LOG_PERMS)"
    fi
else
    security_fail "HIGH" "System log directory missing"
fi

# 9. AI CLI Security Integration
log_message "=== AI CLI Security Assessment ==="

# Check for AI CLI installations and potential security issues
AI_CLIS=("codex" "gemini" "claude")
for cli in "${AI_CLIS[@]}"; do
    check_increment
    if command -v "$cli" >/dev/null 2>&1; then
        security_fail "MEDIUM" "AI CLI '$cli' detected - review with AI security tools"
        which "$cli" >> "$RESULTS_DIR/ai_cli_locations.txt"
        fix_file_ownership "$RESULTS_DIR/ai_cli_locations.txt"
    else
        security_pass "AI CLI '$cli' not found"
    fi
done

# Check for Ollama (resource risk)
check_increment
if pgrep -f "ollama" >/dev/null || command -v ollama >/dev/null 2>&1; then
    security_fail "HIGH" "Ollama local AI detected - significant resource/security risk"
    echo "Ollama status: ACTIVE" >> "$RESULTS_DIR/ai_cli_status.txt"
    fix_file_ownership "$RESULTS_DIR/ai_cli_status.txt"
else
    security_pass "Ollama local AI not detected"
fi

# Check for AI-related directories
AI_DIRS=("$HOME/.ollama" "$HOME/.gemini" "$HOME/.codex" "$HOME/.claude")
for dir in "${AI_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        SIZE=$(du -sh "$dir" 2>/dev/null | cut -f1)
        echo "AI directory: $dir ($SIZE)" >> "$RESULTS_DIR/ai_cli_status.txt"
        fix_file_ownership "$RESULTS_DIR/ai_cli_status.txt"
    fi
done

# Calculate Security Score
calculate_score() {
    log_message "=== Security Score Calculation ==="
    
    # Scoring algorithm (out of 10)
    # Base score of 10, deduct points for issues
    SCORE=10
    
    # Critical issues: -2 points each
    SCORE=$((SCORE - (CRITICAL_ISSUES * 2)))
    
    # High issues: -1 point each  
    SCORE=$((SCORE - HIGH_ISSUES))
    
    # Medium issues: -0.5 points each
    SCORE=$((SCORE - (MEDIUM_ISSUES / 2)))
    
    # Low issues: -0.1 points each
    SCORE=$((SCORE - (LOW_ISSUES / 10)))
    
    # Ensure score doesn't go below 0
    if [ "$SCORE" -lt 0 ]; then
        SCORE=0
    fi
    
    # Security rating description
    if [ "$SCORE" -ge 9 ]; then
        RATING="EXCELLENT"
        RATING_COLOR="$GREEN"
    elif [ "$SCORE" -ge 7 ]; then
        RATING="GOOD" 
        RATING_COLOR="$GREEN"
    elif [ "$SCORE" -ge 5 ]; then
        RATING="FAIR"
        RATING_COLOR="$YELLOW"
    elif [ "$SCORE" -ge 3 ]; then
        RATING="POOR"
        RATING_COLOR="$RED"
    else
        RATING="CRITICAL"
        RATING_COLOR="$RED"
    fi
    
    echo ""
    echo "=== SECURITY SCORE ==="
    echo -e "Score: ${RATING_COLOR}$SCORE/10 ($RATING)${NC}"
    echo ""
    
    # Write detailed scoring to file
    cat > "$SCORE_FILE" << EOF
Security Audit Score: $SCORE/10 ($RATING)
Generated: $(date)

ISSUE BREAKDOWN:
Critical Issues: $CRITICAL_ISSUES (-$(( CRITICAL_ISSUES * 2 )) points)
High Issues: $HIGH_ISSUES (-$HIGH_ISSUES points)  
Medium Issues: $MEDIUM_ISSUES (-$(( MEDIUM_ISSUES / 2 )) points)
Low Issues: $LOW_ISSUES (-$(( LOW_ISSUES / 10 )) points)

CHECKS SUMMARY:
Total Checks: $TOTAL_CHECKS
Passed: $PASSED_CHECKS
Failed: $(( CRITICAL_ISSUES + HIGH_ISSUES + MEDIUM_ISSUES + LOW_ISSUES ))
Pass Rate: $(( (PASSED_CHECKS * 100) / TOTAL_CHECKS ))%
EOF
    
    # Iron Gate ownership correction
    fix_file_ownership "$SCORE_FILE"
}

# Generate recommendations
generate_recommendations() {
    log_message "=== Generating Security Recommendations ==="
    
    RECOMMENDATIONS_FILE="$RESULTS_DIR/security_recommendations.txt"
    
    cat > "$RECOMMENDATIONS_FILE" << EOF
SECURITY HARDENING RECOMMENDATIONS
Generated: $(date)
Current Score: $SCORE/10 ($RATING)

=== IMMEDIATE ACTIONS (Critical/High Issues) ===
EOF
    
    if [ "$CRITICAL_ISSUES" -gt 0 ]; then
        echo "" >> "$RECOMMENDATIONS_FILE"
        echo "CRITICAL PRIORITY:" >> "$RECOMMENDATIONS_FILE"
        grep "CRITICAL:" "$AUDIT_LOG" | sed 's/.*CRITICAL: /• /' >> "$RECOMMENDATIONS_FILE"
    fi
    
    if [ "$HIGH_ISSUES" -gt 0 ]; then
        echo "" >> "$RECOMMENDATIONS_FILE"
        echo "HIGH PRIORITY:" >> "$RECOMMENDATIONS_FILE"
        grep "HIGH:" "$AUDIT_LOG" | sed 's/.*HIGH: /• /' >> "$RECOMMENDATIONS_FILE"
    fi
    
    cat >> "$RECOMMENDATIONS_FILE" << EOF

=== MEDIUM PRIORITY IMPROVEMENTS ===
EOF
    
    if [ "$MEDIUM_ISSUES" -gt 0 ]; then
        grep "MEDIUM:" "$AUDIT_LOG" | sed 's/.*MEDIUM: /• /' >> "$RECOMMENDATIONS_FILE"
    else
        echo "• No medium priority issues found" >> "$RECOMMENDATIONS_FILE"
    fi
    
    cat >> "$RECOMMENDATIONS_FILE" << EOF

=== SUGGESTED HARDENING COMMANDS ===

# Update system packages
sudo apt update && sudo apt upgrade -y

# Enable UFW firewall if not active  
sudo ufw enable
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Secure SSH configuration
sudo sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# AI CLI security (if applicable)
# Run AI security audit: ~/repos/security/bin/detect_ollama.sh
# Block Google telemetry: ~/repos/security/bin/block_telemetry.sh  
# Monitor MCP activity: ~/repos/security/bin/monitor_mcp.sh

=== MONITORING RECOMMENDATIONS ===

# Set up regular security audits
echo "0 6 * * 0 $PWD/$(basename $0) >> /var/log/security_audit.log 2>&1" | sudo tee -a /etc/crontab

# Monitor system logs
sudo tail -f /var/log/auth.log | grep -E "(Failed|Invalid)"

# Check for rootkits
sudo apt install rkhunter chkrootkit
sudo rkhunter --check
sudo chkrootkit

=== SCORE IMPROVEMENT TARGETS ===

Current: $SCORE/10
Target: 8+/10

To reach target score:
- Resolve all critical issues immediately  
- Address high priority issues within 1 week
- Implement continuous monitoring
- Regular security updates and patches
EOF

    # Iron Gate ownership correction
    fix_file_ownership "$RECOMMENDATIONS_FILE"
    echo "Recommendations saved to: $RECOMMENDATIONS_FILE"
}

# Main execution
calculate_score
generate_recommendations

echo ""
echo "=== AUDIT COMPLETE ==="
echo -e "Security Score: ${RATING_COLOR}$SCORE/10 ($RATING)${NC}"
echo "Total Issues: $(( CRITICAL_ISSUES + HIGH_ISSUES + MEDIUM_ISSUES + LOW_ISSUES ))"
echo "Results directory: $RESULTS_DIR"
echo ""
echo "Key files:"
echo "  - $SCORE_FILE"
echo "  - $RESULTS_DIR/security_recommendations.txt"
echo "  - $AUDIT_LOG"

# Return appropriate exit code
if [ "$CRITICAL_ISSUES" -gt 0 ]; then
    exit 2  # Critical issues found
elif [ "$HIGH_ISSUES" -gt 0 ]; then
    exit 1  # High issues found  
else
    exit 0  # No critical/high issues
fi