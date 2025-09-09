#!/bin/bash
# security_hub.sh - Simple central orchestration for AI security toolkit
# Created: 2025-09-06
# Purpose: MVP security hub with basic path configuration and tool orchestration

set -euo pipefail

# ======================
# PATH CONFIGURATION
# ======================

# Base paths (can be overridden by environment variables)
SECURITY_BASE="${SECURITY_BASE:-$(dirname "$(readlink -f "$0")")}"
SECURITY_BIN="${SECURITY_BIN:-$SECURITY_BASE/bin}"
SECURITY_DOCS="${SECURITY_DOCS:-$SECURITY_BASE/docs}"
SECURITY_CONFIG="${SECURITY_CONFIG:-$SECURITY_BASE/config}"
SECURITY_RESULTS="${SECURITY_RESULTS:-$SECURITY_BASE/results}"
SECURITY_EGGS="${SECURITY_EGGS:-$SECURITY_BASE/.eggs}"

# Optional enhancement tools (graceful degradation if missing)
BOXY_PATH="${BOXY_PATH:-/home/xnull/.local/bin/odx/boxy}"
JYNX_PATH="${JYNX_PATH:-/home/xnull/.local/bin/odx/jynx}"

# Create necessary directories
mkdir -p "$SECURITY_RESULTS"

# ======================
# COLORS & FORMATTING
# ======================

# Simple colors for basic UI (fallback if no boxy)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ======================
# UTILITY FUNCTIONS
# ======================

print_header() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}   AI SECURITY HUB - Command Center${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo ""
}

print_menu() {
    echo -e "${GREEN}Main Menu:${NC}"
    echo ""
    echo "  1) 🛡️  Run Security Audit (General)"
    echo "  2) 🎨  Run Enhanced Audit (Visual)"
    echo "  3) 🔍  Detect AI CLIs"
    echo "  4) 📊  Check Subscription Quotas"
    echo "  5) 🚨  Emergency Response"
    echo "  6) 📈  Baseline Monitoring"
    echo "  7) 🧪  Test AI APIs"
    echo "  8) 📚  View Documentation"
    echo "  9) ⚙️  Configuration Check"
    echo "  0) Exit"
    echo ""
}

check_dependencies() {
    echo -e "${BLUE}Checking dependencies...${NC}"
    
    local deps_ok=true
    
    # Check core scripts
    if [[ -d "$SECURITY_BIN" ]]; then
        local script_count=$(find "$SECURITY_BIN" -name "*.sh" -type f | wc -l)
        echo -e "  ✅ Found $script_count security scripts"
    else
        echo -e "  ${RED}❌ Security scripts directory not found${NC}"
        deps_ok=false
    fi
    
    # Check optional enhancements
    if [[ -x "$BOXY_PATH" ]]; then
        echo -e "  ✅ Boxy visual enhancement available"
    else
        echo -e "  ${YELLOW}⚠️  Boxy not found (visual features disabled)${NC}"
    fi
    
    if [[ -x "$JYNX_PATH" ]]; then
        echo -e "  ✅ Jynx syntax highlighting available"
    else
        echo -e "  ${YELLOW}⚠️  Jynx not found (syntax highlighting disabled)${NC}"
    fi
    
    # Check for root access (some tools need it)
    if [[ $EUID -eq 0 ]]; then
        echo -e "  ✅ Running with root privileges"
    else
        echo -e "  ${YELLOW}⚠️  Not running as root (some checks may fail)${NC}"
    fi
    
    echo ""
    
    if [[ "$deps_ok" == "false" ]]; then
        echo -e "${RED}Critical dependencies missing. Exiting.${NC}"
        exit 1
    fi
}

run_script() {
    local script="$1"
    local description="$2"
    
    echo -e "${BLUE}Running: $description${NC}"
    echo -e "${CYAN}────────────────────────────────────────${NC}"
    
    if [[ -f "$SECURITY_BIN/$script" ]]; then
        "$SECURITY_BIN/$script"
    else
        echo -e "${RED}Error: Script not found: $script${NC}"
        return 1
    fi
    
    echo ""
    echo -e "${GREEN}Complete. Press Enter to continue...${NC}"
    read -r
}

show_emergency_menu() {
    echo -e "${RED}═══════════════════════════════════════════${NC}"
    echo -e "${RED}   EMERGENCY RESPONSE MENU${NC}"
    echo -e "${RED}═══════════════════════════════════════════${NC}"
    echo ""
    echo "  1) 🔒 Block Google Telemetry"
    echo "  2) 🗑️  Disable Ollama"
    echo "  3) 👁️  Monitor MCP Activity"
    echo "  4) 📡 Capture Telemetry Traffic"
    echo "  5) 🔙 Back to Main Menu"
    echo ""
    echo -n "Select emergency action: "
}

show_test_menu() {
    echo -e "${BLUE}API Testing Menu:${NC}"
    echo ""
    echo "  1) Test OpenAI API"
    echo "  2) Test Gemini API"
    echo "  3) Test Claude API"
    echo "  4) Test All APIs"
    echo "  5) Back to Main Menu"
    echo ""
    echo -n "Select test: "
}

view_documentation() {
    echo -e "${CYAN}Available Documentation:${NC}"
    echo ""
    
    if [[ -d "$SECURITY_DOCS" ]]; then
        echo "Main docs:"
        ls -1 "$SECURITY_DOCS"/*.txt 2>/dev/null | head -10 | sed 's|.*/||'
        echo ""
        echo "Advanced docs:"
        ls -1 "$SECURITY_DOCS"/advanced/*.txt 2>/dev/null | head -5 | sed 's|.*/||'
    fi
    
    echo ""
    echo "Enter filename to view (or 'back' to return): "
    read -r docfile
    
    if [[ "$docfile" != "back" ]]; then
        if [[ -f "$SECURITY_DOCS/$docfile" ]]; then
            less "$SECURITY_DOCS/$docfile"
        elif [[ -f "$SECURITY_DOCS/advanced/$docfile" ]]; then
            less "$SECURITY_DOCS/advanced/$docfile"
        else
            echo -e "${RED}File not found${NC}"
        fi
    fi
}

show_config() {
    echo -e "${CYAN}Current Configuration:${NC}"
    echo ""
    echo "  SECURITY_BASE:    $SECURITY_BASE"
    echo "  SECURITY_BIN:     $SECURITY_BIN"
    echo "  SECURITY_DOCS:    $SECURITY_DOCS"
    echo "  SECURITY_CONFIG:  $SECURITY_CONFIG"
    echo "  SECURITY_RESULTS: $SECURITY_RESULTS"
    echo "  SECURITY_EGGS:    $SECURITY_EGGS"
    echo ""
    echo "  BOXY_PATH: $BOXY_PATH $([ -x "$BOXY_PATH" ] && echo "✅" || echo "❌")"
    echo "  JYNX_PATH: $JYNX_PATH $([ -x "$JYNX_PATH" ] && echo "✅" || echo "❌")"
    echo ""
    echo "  Running as: $(whoami)"
    echo "  Hostname: $(hostname)"
    echo "  Date: $(date)"
    echo ""
    echo "Press Enter to continue..."
    read -r
}

# ======================
# MAIN PROGRAM
# ======================

main() {
    # Initial setup
    clear
    print_header
    check_dependencies
    
    # Main loop
    while true; do
        print_menu
        echo -n "Select option: "
        read -r choice
        
        case $choice in
            1)
                run_script "general_security_audit.sh" "General Security Audit"
                ;;
            2)
                if [[ -f "$SECURITY_BIN/general_security_audit_enhanced.sh" ]]; then
                    run_script "general_security_audit_enhanced.sh" "Enhanced Visual Audit"
                else
                    echo -e "${YELLOW}Enhanced audit not available, running standard...${NC}"
                    run_script "general_security_audit.sh" "General Security Audit"
                fi
                ;;
            3)
                echo -e "${BLUE}AI CLI Detection:${NC}"
                run_script "detect_ollama.sh" "Ollama Detection" 2>/dev/null || true
                echo "Checking for other AI CLIs..."
                for cli in codex gemini claude; do
                    if command -v "$cli" >/dev/null 2>&1; then
                        echo -e "  ${YELLOW}⚠️  Found: $cli at $(which $cli)${NC}"
                    fi
                done
                echo "Press Enter to continue..."
                read -r
                ;;
            4)
                run_script "subscription_quota_monitor.sh" "Subscription Quota Check"
                ;;
            5)
                show_emergency_menu
                read -r emerg_choice
                case $emerg_choice in
                    1) run_script "block_telemetry.sh" "Block Google Telemetry" ;;
                    2) run_script "disable_ollama.sh" "Disable Ollama" ;;
                    3) run_script "monitor_mcp.sh" "Monitor MCP Activity" ;;
                    4) run_script "capture_telemetry.sh" "Capture Telemetry" ;;
                    5) continue ;;
                esac
                ;;
            6)
                run_script "baseline_monitor.sh" "Baseline Monitoring"
                ;;
            7)
                show_test_menu
                read -r test_choice
                case $test_choice in
                    1) run_script "test_openai.sh" "OpenAI API Test" ;;
                    2) run_script "test_gemini.sh" "Gemini API Test" ;;
                    3) run_script "test_claude.sh" "Claude API Test" ;;
                    4) 
                        run_script "test_openai.sh" "OpenAI API Test"
                        run_script "test_gemini.sh" "Gemini API Test"
                        run_script "test_claude.sh" "Claude API Test"
                        ;;
                    5) continue ;;
                esac
                ;;
            8)
                view_documentation
                ;;
            9)
                show_config
                ;;
            0)
                echo -e "${GREEN}Exiting Security Hub. Stay vigilant!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                sleep 1
                ;;
        esac
        
        clear
        print_header
    done
}

# ======================
# ENTRY POINT
# ======================

# Handle help flag
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "AI Security Hub - Central command for security toolkit"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --help, -h     Show this help message"
    echo "  --config       Show configuration only"
    echo "  --quick        Run quick security audit and exit"
    echo ""
    echo "Environment variables:"
    echo "  SECURITY_BASE    Override base directory"
    echo "  SECURITY_BIN     Override scripts directory"
    echo "  BOXY_PATH        Path to boxy executable"
    echo "  JYNX_PATH        Path to jynx executable"
    exit 0
fi

# Handle config flag
if [[ "${1:-}" == "--config" ]]; then
    show_config
    exit 0
fi

# Handle quick audit flag
if [[ "${1:-}" == "--quick" ]]; then
    check_dependencies
    run_script "general_security_audit.sh" "Quick Security Audit"
    exit 0
fi

# Run main program
main