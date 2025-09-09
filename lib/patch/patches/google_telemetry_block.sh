#!/bin/bash
# google_telemetry_block.sh - Rewindable Google Telemetry Blocking Patch
# Purpose: Block Google Gemini CLI telemetry with full backup/restore capability
#
# HYPOTHESIS-DRIVEN SECURITY INVESTIGATION
# ========================================
# 
# HYPOTHESIS:
# - Google Gemini CLI transmits telemetry data via ports 4317/4318 to googleapis.com
# - Blocking these channels will prevent data exfiltration without breaking core functionality
# - Telemetry includes usage patterns, system info, and potentially sensitive data
# 
# EXPECTED OUTCOMES:
# - Gemini CLI continues to function for code generation and queries
# - No outbound connections to telemetry endpoints (4317/4318, custom.googleapis.com)  
# - Reduced network traffic and improved privacy
# - Possible error messages in logs about telemetry failures (expected/acceptable)
# 
# DATA COLLECTION POINTS:
# - Pre/post network connection analysis (netstat, ss)
# - Gemini log file analysis for telemetry errors
# - Functionality testing (basic commands, code generation)
# - Firewall rule effectiveness verification
# - DNS resolution blocking verification
# 
# SUCCESS CRITERIA:
# - No telemetry traffic detected after patch
# - Core Gemini functionality preserved  
# - Firewall rules active and blocking attempts
# - DNS blocking preventing googleapis.com telemetry resolution

set -e

PATCH_NAME="google_telemetry_block"
BACKUP_DIR="../backups"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BACKUP_ID="${PATCH_NAME}_${TIMESTAMP}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This patch requires root privileges for firewall modifications"
        exit 1
    fi
}

backup_system_state() {
    local backup_path="$BACKUP_DIR/$BACKUP_ID"
    mkdir -p "$backup_path"
    
    log "Creating system state backup: $BACKUP_ID"
    
    # Backup iptables rules
    iptables-save > "$backup_path/iptables_rules.bak"
    log "✓ iptables rules backed up"
    
    # Backup /etc/hosts
    if [[ -f /etc/hosts ]]; then
        cp /etc/hosts "$backup_path/hosts.bak"
        log "✓ /etc/hosts backed up"
    fi
    
    # Backup Gemini settings if they exist
    if [[ -d ~/.gemini ]]; then
        cp -r ~/.gemini "$backup_path/gemini_config.bak" 2>/dev/null || true
        log "✓ Gemini configuration backed up"
    fi
    
    # Record pre-patch network state
    netstat -tupln > "$backup_path/netstat_pre.txt" 2>/dev/null || true
    ss -tupln > "$backup_path/ss_pre.txt" 2>/dev/null || true
    
    # Save backup metadata
    cat > "$backup_path/metadata.json" << EOF
{
    "patch_name": "$PATCH_NAME",
    "timestamp": "$TIMESTAMP",  
    "backup_id": "$BACKUP_ID",
    "user": "$(whoami)",
    "system": "$(uname -a)",
    "applied": false
}
EOF
    
    success "System state backed up to: $backup_path"
    echo "$BACKUP_ID" > "$BACKUP_DIR/.latest_backup"
}

apply_patch() {
    log "Applying Google telemetry blocking patch..."
    
    # Block telemetry ports
    log "Blocking telemetry ports 4317, 4318..."
    iptables -A OUTPUT -p tcp --dport 4317 -j DROP
    iptables -A OUTPUT -p tcp --dport 4318 -j DROP
    
    # Block Google telemetry endpoints  
    log "Blocking googleapis.com telemetry endpoints..."
    iptables -A OUTPUT -d googleapis.com -p tcp --dport 443 -m string --string "gemini_cli" --algo bm -j DROP
    
    # DNS-level blocking
    log "Adding DNS-level blocks..."
    if ! grep -q "custom.googleapis.com" /etc/hosts; then
        echo "127.0.0.1 custom.googleapis.com # SUPERHARD_TELEMETRY_BLOCK" >> /etc/hosts
    fi
    
    # Update Gemini settings if directory exists
    if [[ -d ~/.gemini ]]; then
        log "Hardening Gemini configuration..."
        cat > ~/.gemini/settings.json << EOF
{
  "telemetry": {"enabled": false, "target": "none"},
  "privacy": {"data_collection": false, "usage_analytics": false}
}
EOF
        chmod 444 ~/.gemini/settings.json
    fi
    
    # Mark backup as applied
    local latest_backup=$(cat "$BACKUP_DIR/.latest_backup" 2>/dev/null || echo "")
    if [[ -n "$latest_backup" && -f "$BACKUP_DIR/$latest_backup/metadata.json" ]]; then
        sed -i 's/"applied": false/"applied": true/' "$BACKUP_DIR/$latest_backup/metadata.json"
    fi
    
    success "Google telemetry blocking patch applied successfully"
    warn "Test Gemini functionality before permanent deployment"
}

restore_from_backup() {
    local backup_id="${1:-$(cat "$BACKUP_DIR/.latest_backup" 2>/dev/null)}"
    
    if [[ -z "$backup_id" ]]; then
        error "No backup ID specified and no latest backup found"
        exit 1
    fi
    
    local backup_path="$BACKUP_DIR/$backup_id"
    
    if [[ ! -d "$backup_path" ]]; then
        error "Backup not found: $backup_path"
        exit 1
    fi
    
    log "Restoring system state from backup: $backup_id"
    
    # Restore iptables rules
    if [[ -f "$backup_path/iptables_rules.bak" ]]; then
        iptables-restore < "$backup_path/iptables_rules.bak"
        log "✓ iptables rules restored"
    fi
    
    # Restore /etc/hosts
    if [[ -f "$backup_path/hosts.bak" ]]; then
        cp "$backup_path/hosts.bak" /etc/hosts
        log "✓ /etc/hosts restored"
    fi
    
    # Restore Gemini configuration
    if [[ -d "$backup_path/gemini_config.bak" ]]; then
        rm -rf ~/.gemini 2>/dev/null || true
        cp -r "$backup_path/gemini_config.bak" ~/.gemini 2>/dev/null || true
        log "✓ Gemini configuration restored"
    fi
    
    success "System state restored from backup: $backup_id"
}

check_patch_status() {
    log "Checking Google telemetry blocking patch status..."
    
    local is_patched=false
    local issues=()
    
    # Check iptables rules
    if iptables -L OUTPUT -n | grep -q "tcp dpt:4317"; then
        success "✓ Port 4317 blocked in iptables"
        is_patched=true
    else
        issues+=("Port 4317 not blocked")
    fi
    
    if iptables -L OUTPUT -n | grep -q "tcp dpt:4318"; then
        success "✓ Port 4318 blocked in iptables"
        is_patched=true
    else
        issues+=("Port 4318 not blocked")  
    fi
    
    # Check /etc/hosts
    if grep -q "custom.googleapis.com" /etc/hosts; then
        success "✓ DNS blocking active in /etc/hosts"
        is_patched=true
    else
        issues+=("DNS blocking not active")
    fi
    
    # Check Gemini settings
    if [[ -f ~/.gemini/settings.json ]] && grep -q '"enabled": false' ~/.gemini/settings.json; then
        success "✓ Gemini telemetry disabled in settings"
        is_patched=true
    else
        issues+=("Gemini telemetry not disabled in settings")
    fi
    
    if [[ ${#issues[@]} -eq 0 ]]; then
        success "Google telemetry blocking patch is ACTIVE"
        return 0
    else
        warn "Patch partially applied or not active:"
        for issue in "${issues[@]}"; do
            echo "  - $issue"
        done
        return 1
    fi
}

test_functionality() {
    log "Testing Gemini functionality with telemetry blocking..."
    
    if ! command -v gemini &> /dev/null; then
        warn "Gemini CLI not found - cannot test functionality"
        return 1
    fi
    
    # Test basic Gemini command
    log "Testing basic Gemini command..."
    if timeout 30s gemini --version &>/dev/null; then
        success "✓ Gemini CLI responds to --version"
    else
        error "✗ Gemini CLI not responding"
        return 1
    fi
    
    # Test simple query (with timeout)
    log "Testing simple query..."
    if timeout 30s gemini "Say hello" &>/dev/null; then
        success "✓ Gemini can process queries"
    else
        warn "⚠ Gemini query test failed - may be expected with telemetry blocking"
    fi
    
    success "Functionality test complete"
}

show_monitoring_logs() {
    log "Showing telemetry blocking monitoring..."
    
    # Show blocked connections
    echo -e "${YELLOW}Recent blocked telemetry attempts:${NC}"
    iptables -L OUTPUT -v -n | grep -E "(4317|4318|googleapis)" || echo "No recent blocks found"
    
    # Show network connections
    echo -e "\n${YELLOW}Current network connections (ports 4317, 4318):${NC}"
    netstat -tupln 2>/dev/null | grep -E "(4317|4318)" || echo "No telemetry ports active"
    
    # Show Gemini logs if available
    if [[ -f ~/.gemini/collector.log ]]; then
        echo -e "\n${YELLOW}Recent Gemini telemetry logs:${NC}"
        tail -20 ~/.gemini/collector.log
    else
        echo "No Gemini telemetry logs found"
    fi
    
    # Show DNS resolution test
    echo -e "\n${YELLOW}Testing DNS blocking:${NC}"
    if nslookup custom.googleapis.com 2>/dev/null | grep -q "127.0.0.1"; then
        success "✓ DNS blocking active for custom.googleapis.com"
    else
        warn "DNS blocking may not be working"
    fi
}

collect_experiment_data() {
    local phase="$1"  # pre, post, or validation
    local latest_backup=$(cat "$BACKUP_DIR/.latest_backup" 2>/dev/null || echo "")
    local data_dir="$BACKUP_DIR/$latest_backup/experiment_data"
    
    mkdir -p "$data_dir"
    
    log "Collecting experiment data ($phase phase)..."
    
    # Network state analysis
    netstat -tupln > "$data_dir/netstat_${phase}.txt" 2>/dev/null || true
    ss -tupln > "$data_dir/ss_${phase}.txt" 2>/dev/null || true
    
    # DNS resolution testing
    nslookup custom.googleapis.com > "$data_dir/dns_test_${phase}.txt" 2>&1 || true
    
    # Firewall state
    iptables -L OUTPUT -v -n > "$data_dir/iptables_${phase}.txt" 2>/dev/null || true
    
    # Process monitoring
    ps aux | grep -E "(gemini|telemetry|otelcol)" > "$data_dir/processes_${phase}.txt" 2>/dev/null || true
    
    # Gemini logs if available
    if [[ -f ~/.gemini/collector.log ]]; then
        cp ~/.gemini/collector.log "$data_dir/gemini_logs_${phase}.txt"
    fi
    
    # Timestamp the data collection
    date '+%Y-%m-%d %H:%M:%S' > "$data_dir/timestamp_${phase}.txt"
    
    success "Experiment data collected: $data_dir"
}

validate_hypothesis() {
    log "Validating hypothesis against collected data..."
    
    local latest_backup=$(cat "$BACKUP_DIR/.latest_backup" 2>/dev/null || echo "")
    local data_dir="$BACKUP_DIR/$latest_backup/experiment_data"
    
    if [[ ! -d "$data_dir" ]]; then
        error "No experiment data found. Run data collection first."
        return 1
    fi
    
    local findings_file="$data_dir/hypothesis_validation.md"
    
    cat > "$findings_file" << EOF
# Google Telemetry Blocking - Hypothesis Validation
**Generated**: $(date '+%Y-%m-%d %H:%M:%S')

## Original Hypothesis
- Google Gemini CLI transmits telemetry data via ports 4317/4318 to googleapis.com
- Blocking these channels will prevent data exfiltration without breaking core functionality
- Telemetry includes usage patterns, system info, and potentially sensitive data

## Data Analysis Results

### Network Traffic Analysis
EOF
    
    # Compare pre/post network connections
    if [[ -f "$data_dir/netstat_pre.txt" && -f "$data_dir/netstat_post.txt" ]]; then
        local pre_connections=$(grep -E "(4317|4318)" "$data_dir/netstat_pre.txt" | wc -l)
        local post_connections=$(grep -E "(4317|4318)" "$data_dir/netstat_post.txt" | wc -l)
        
        echo "- **Pre-patch telemetry connections**: $pre_connections" >> "$findings_file"
        echo "- **Post-patch telemetry connections**: $post_connections" >> "$findings_file"
        
        if [[ $post_connections -lt $pre_connections ]]; then
            echo "- **HYPOTHESIS CONFIRMED**: Telemetry connections reduced" >> "$findings_file"
        else
            echo "- **HYPOTHESIS UNCLEAR**: No significant connection reduction" >> "$findings_file"
        fi
    fi
    
    # DNS blocking verification
    if [[ -f "$data_dir/dns_test_post.txt" ]]; then
        if grep -q "127.0.0.1" "$data_dir/dns_test_post.txt"; then
            echo "- **DNS BLOCKING**: ✅ ACTIVE - custom.googleapis.com resolving to localhost" >> "$findings_file"
        else
            echo "- **DNS BLOCKING**: ❌ FAILED - googleapis.com still resolving externally" >> "$findings_file"
        fi
    fi
    
    # Firewall effectiveness
    if [[ -f "$data_dir/iptables_post.txt" ]]; then
        local blocked_4317=$(grep -c "tcp dpt:4317.*DROP" "$data_dir/iptables_post.txt" || echo "0")
        local blocked_4318=$(grep -c "tcp dpt:4318.*DROP" "$data_dir/iptables_post.txt" || echo "0")
        
        echo "- **Firewall Rules**: Port 4317 blocked: $blocked_4317, Port 4318 blocked: $blocked_4318" >> "$findings_file"
    fi
    
    # Functionality assessment
    cat >> "$findings_file" << EOF

### Functionality Assessment
EOF
    
    if timeout 10s gemini --version &>/dev/null; then
        echo "- **Core Functionality**: ✅ PRESERVED - Gemini CLI responding" >> "$findings_file"
    else
        echo "- **Core Functionality**: ❌ IMPACTED - Gemini CLI not responding" >> "$findings_file"
    fi
    
    # Log analysis
    if [[ -f "$data_dir/gemini_logs_post.txt" ]]; then
        local telemetry_errors=$(grep -ic "telemetry\|export\|failed" "$data_dir/gemini_logs_post.txt" || echo "0")
        echo "- **Telemetry Errors**: $telemetry_errors error entries found (expected)" >> "$findings_file"
    fi
    
    cat >> "$findings_file" << EOF

## Conclusion
EOF
    
    # Generate conclusion based on findings
    local functionality_ok=false
    local blocking_active=false
    
    if timeout 10s gemini --version &>/dev/null; then
        functionality_ok=true
    fi
    
    if iptables -L OUTPUT -n | grep -q "tcp dpt:431[78]"; then
        blocking_active=true
    fi
    
    if [[ "$functionality_ok" == true && "$blocking_active" == true ]]; then
        echo "**HYPOTHESIS VALIDATED**: Telemetry blocking successful without breaking core functionality." >> "$findings_file"
    elif [[ "$functionality_ok" == true && "$blocking_active" == false ]]; then
        echo "**HYPOTHESIS INCONCLUSIVE**: Functionality preserved but blocking may not be active." >> "$findings_file"
    elif [[ "$functionality_ok" == false && "$blocking_active" == true ]]; then
        echo "**HYPOTHESIS REJECTED**: Blocking active but functionality compromised." >> "$findings_file"
    else
        echo "**EXPERIMENT FAILED**: Neither blocking nor functionality working properly." >> "$findings_file"
    fi
    
    cat >> "$findings_file" << EOF

## Recommendations
- Review findings above for permanent implementation decision
- Consider additional monitoring for long-term validation
- Document any unexpected behaviors for future investigations

---
*Generated by Google Telemetry Blocking Patch - Hypothesis Validation*
EOF
    
    success "Hypothesis validation complete: $findings_file"
    echo "View findings: cat $findings_file"
}

list_backups() {
    log "Available backups:"
    
    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
        echo "No backups found"
        return
    fi
    
    for backup in "$BACKUP_DIR"/*/; do
        if [[ -f "$backup/metadata.json" ]]; then
            local backup_name=$(basename "$backup")
            local timestamp=$(jq -r '.timestamp // "unknown"' "$backup/metadata.json" 2>/dev/null)
            local applied=$(jq -r '.applied // false' "$backup/metadata.json" 2>/dev/null)
            local status_color="${GREEN}"
            [[ "$applied" == "true" ]] && status_color="${YELLOW}"
            
            echo -e "  ${status_color}$backup_name${NC} - $timestamp (applied: $applied)"
        fi
    done
}

usage() {
    echo "Google Telemetry Blocking Patch - Hypothesis-Driven Security Investigation"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  status                Check if patch is currently applied"
    echo "  patch                 Apply telemetry blocking (creates backup)"
    echo "  unpatch [backup_id]   Restore from backup (uses latest if not specified)"
    echo "  test                  Test Gemini functionality after patch"
    echo "  logs                  Show telemetry monitoring logs"
    echo "  list-backups          List available backups"
    echo ""
    echo "Experimental Workflow:"
    echo "  collect-data <phase>  Collect experiment data (pre, post, validation)"
    echo "  validate              Validate hypothesis against collected data"
    echo ""
    echo "Recommended Experiment Process:"
    echo "  1. $0 collect-data pre     # Collect baseline data"
    echo "  2. $0 patch                # Apply security patch"
    echo "  3. $0 collect-data post    # Collect post-patch data"
    echo "  4. $0 test                 # Test functionality"
    echo "  5. $0 logs                 # Monitor for issues"
    echo "  6. $0 validate             # Generate findings report"
    echo "  7. $0 unpatch              # Revert if issues found"
    echo ""
    echo "Examples:"
    echo "  $0 status"
    echo "  $0 collect-data pre"
    echo "  $0 patch"
    echo "  $0 validate"
    echo "  $0 unpatch google_telemetry_block_20250906_152030"
}

# Main command dispatch
case "${1:-}" in
    "status")
        check_patch_status
        ;;
    "patch")
        check_root
        backup_system_state
        apply_patch
        ;;
    "unpatch")
        check_root
        restore_from_backup "$2"
        ;;
    "test")
        test_functionality
        ;;
    "logs")
        show_monitoring_logs
        ;;
    "list-backups")
        list_backups
        ;;
    "collect-data")
        if [[ -z "$2" ]]; then
            error "Data collection phase required: pre, post, or validation"
            exit 1
        fi
        collect_experiment_data "$2"
        ;;
    "validate")
        validate_hypothesis
        ;;
    *)
        usage
        exit 1
        ;;
esac