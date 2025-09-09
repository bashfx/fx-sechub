#!/bin/bash
# test_functionality.sh - Test AI CLI functionality after security measures
# Created: 2025-09-06

echo "=== AI CLI Functionality Testing ==="
echo "Testing functionality after security hardening measures..."

RESULTS_FILE="functionality_test_$(date +%Y%m%d_%H%M%S).txt"

# Initialize results file
cat > "$RESULTS_FILE" << EOF
AI CLI Functionality Test Results
Generated: $(date)
===============================

EOF

log_result() {
    echo "$1" | tee -a "$RESULTS_FILE"
}

test_command() {
    local description="$1"
    local command="$2"
    local timeout_duration="${3:-30}"
    
    echo "Testing: $description"
    log_result "TEST: $description"
    
    # Run command with timeout
    if timeout $timeout_duration bash -c "$command" >/dev/null 2>&1; then
        echo "  ✓ PASSED"
        log_result "  RESULT: PASSED"
    else
        echo "  ✗ FAILED"
        log_result "  RESULT: FAILED"
    fi
    
    echo ""
    log_result ""
}

# Test OpenAI Codex
echo "=== Testing OpenAI Codex ==="
log_result "=== OpenAI CODEX TESTS ==="

if command -v codex >/dev/null 2>&1; then
    test_command "Codex basic command" "codex 'Hello, test command'"
    test_command "Codex help display" "codex --help" 10
    test_command "Codex with file operations" "echo 'test' > /tmp/test.txt && codex 'read /tmp/test.txt'"
    test_command "Codex OSS mode (should fail if Ollama disabled)" "codex --oss 'simple test'" 15
    
    # Check if OSS mode actually fails
    if timeout 15 codex --oss "test" >/dev/null 2>&1; then
        echo "  WARNING: OSS mode still works (Ollama may still be active)"
        log_result "  WARNING: OSS mode functional - Ollama may still be running"
    else
        echo "  ✓ OSS mode properly disabled"
        log_result "  SUCCESS: OSS mode disabled as expected"
    fi
else
    echo "Codex not found - skipping tests"
    log_result "Codex not installed - tests skipped"
fi

echo ""

# Test Google Gemini CLI
echo "=== Testing Google Gemini CLI ==="
log_result "=== GOOGLE GEMINI TESTS ==="

if command -v gemini >/dev/null 2>&1; then
    test_command "Gemini basic command" "gemini 'Hello, test command'"
    test_command "Gemini help display" "gemini --help" 10
    test_command "Gemini code generation" "gemini 'write a simple hello world in Python'"
    
    # Test if telemetry blocking affects functionality
    echo "Testing telemetry impact..."
    BEFORE_TIME=$(date +%s)
    if timeout 30 gemini "simple test" >/dev/null 2>&1; then
        AFTER_TIME=$(date +%s)
        DURATION=$((AFTER_TIME - BEFORE_TIME))
        echo "  ✓ Gemini works with telemetry blocked (${DURATION}s)"
        log_result "  SUCCESS: Functionality maintained with telemetry blocked (${DURATION}s response time)"
    else
        echo "  ✗ Gemini may be affected by telemetry blocking"
        log_result "  WARNING: Gemini functionality impacted by telemetry blocking"
    fi
    
    # Check for telemetry errors in output
    GEMINI_OUTPUT=$(timeout 15 gemini "test" 2>&1)
    if echo "$GEMINI_OUTPUT" | grep -qi "telemetry\|otel\|collector"; then
        echo "  WARNING: Telemetry-related messages in output"
        log_result "  WARNING: Telemetry errors detected in output"
    else
        echo "  ✓ No telemetry errors in output"
        log_result "  SUCCESS: No telemetry errors detected"
    fi
else
    echo "Gemini CLI not found - skipping tests"
    log_result "Gemini CLI not installed - tests skipped"
fi

echo ""

# Test Claude CLI (if available)
echo "=== Testing Claude CLI ==="
log_result "=== CLAUDE CLI TESTS ==="

if command -v claude >/dev/null 2>&1; then
    test_command "Claude basic command" "claude 'Hello, test command'"
    test_command "Claude help display" "claude --help" 10
else
    echo "Claude CLI not found - skipping tests"
    log_result "Claude CLI not installed - tests skipped"
fi

echo ""

# Test system resource impact
echo "=== System Resource Impact ==="
log_result "=== SYSTEM RESOURCE ANALYSIS ==="

echo "Checking system resources after security measures..."

# Memory usage
MEM_USAGE=$(free | awk '/Mem/ {printf "%.1f", $3/$2 * 100}')
echo "Memory usage: ${MEM_USAGE}%"
log_result "Memory usage: ${MEM_USAGE}%"

# CPU usage
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
echo "CPU usage: ${CPU_USAGE}%"
log_result "CPU usage: ${CPU_USAGE}%"

# Disk space
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}')
echo "Disk usage: $DISK_USAGE"
log_result "Disk usage: $DISK_USAGE"

# Check for AI-related processes
AI_PROCESSES=$(ps aux | grep -E "(codex|gemini|claude|ollama|mcp|otel)" | grep -v grep | wc -l)
echo "AI-related processes: $AI_PROCESSES"
log_result "AI-related processes: $AI_PROCESSES"

echo ""

# Network connectivity test
echo "=== Network Connectivity ==="
log_result "=== NETWORK CONNECTIVITY ==="

echo "Testing network connectivity to AI services..."

# Test connectivity to main AI APIs
API_ENDPOINTS=(
    "api.openai.com:443"
    "api.anthropic.com:443"
    "generativelanguage.googleapis.com:443"
)

for endpoint in "${API_ENDPOINTS[@]}"; do
    host=$(echo $endpoint | cut -d: -f1)
    port=$(echo $endpoint | cut -d: -f2)
    
    if timeout 5 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
        echo "  ✓ $host reachable"
        log_result "  SUCCESS: $host reachable"
    else
        echo "  ✗ $host unreachable"
        log_result "  WARNING: $host unreachable"
    fi
done

# Test blocked telemetry ports
BLOCKED_PORTS=(4317 4318 11434 16686)
echo ""
echo "Verifying blocked services..."

for port in "${BLOCKED_PORTS[@]}"; do
    if timeout 2 bash -c "echo >/dev/tcp/localhost/$port" 2>/dev/null; then
        echo "  ✗ WARNING: Port $port is responding (should be blocked)"
        log_result "  WARNING: Port $port responding - blocking may have failed"
    else
        echo "  ✓ Port $port properly blocked"
        log_result "  SUCCESS: Port $port properly blocked"
    fi
done

echo ""

# Security validation
echo "=== Security Validation ==="
log_result "=== SECURITY VALIDATION ==="

# Check for telemetry processes
TELEMETRY_PROCS=$(ps aux | grep -E "(otelcol|jaeger|telemetry)" | grep -v grep | wc -l)
if [ $TELEMETRY_PROCS -eq 0 ]; then
    echo "  ✓ No telemetry processes running"
    log_result "  SUCCESS: No telemetry processes detected"
else
    echo "  ✗ WARNING: $TELEMETRY_PROCS telemetry processes still running"
    log_result "  WARNING: $TELEMETRY_PROCS telemetry processes still active"
fi

# Check for Ollama processes
OLLAMA_PROCS=$(ps aux | grep ollama | grep -v grep | wc -l)
if [ $OLLAMA_PROCS -eq 0 ]; then
    echo "  ✓ No Ollama processes running"
    log_result "  SUCCESS: No Ollama processes detected"
else
    echo "  ✗ WARNING: $OLLAMA_PROCS Ollama processes still running"
    log_result "  WARNING: $OLLAMA_PROCS Ollama processes still active"
fi

# Check disk space recovery
if [ -d ~/.ollama ]; then
    OLLAMA_SIZE=$(du -sh ~/.ollama 2>/dev/null | cut -f1)
    echo "  Ollama data remaining: $OLLAMA_SIZE"
    log_result "  INFO: Ollama data remaining: $OLLAMA_SIZE"
else
    echo "  ✓ Ollama directory removed"
    log_result "  SUCCESS: Ollama directory fully removed"
fi

echo ""

# Performance comparison (if baseline exists)
echo "=== Performance Analysis ==="
log_result "=== PERFORMANCE ANALYSIS ==="

echo "Note: Run this test before and after security measures for comparison"
log_result "Performance baseline comparison requires before/after measurements"

# Simple performance test
PERF_START=$(date +%s.%N)
sleep 1  # Placeholder for actual AI command
PERF_END=$(date +%s.%N)
PERF_DURATION=$(echo "$PERF_END - $PERF_START" | bc)

echo "Test duration: ${PERF_DURATION}s"
log_result "Sample test duration: ${PERF_DURATION}s"

echo ""

# Generate summary
echo "=== Test Summary ==="
log_result "=== TEST SUMMARY ==="

TOTAL_TESTS=$(grep -c "TEST:" "$RESULTS_FILE")
PASSED_TESTS=$(grep -c "RESULT: PASSED" "$RESULTS_FILE")
FAILED_TESTS=$(grep -c "RESULT: FAILED" "$RESULTS_FILE")
WARNINGS=$(grep -c "WARNING:" "$RESULTS_FILE")

echo "Total tests: $TOTAL_TESTS"
echo "Passed: $PASSED_TESTS"
echo "Failed: $FAILED_TESTS" 
echo "Warnings: $WARNINGS"

log_result "Total tests: $TOTAL_TESTS"
log_result "Passed: $PASSED_TESTS"
log_result "Failed: $FAILED_TESTS"
log_result "Warnings: $WARNINGS"

if [ $FAILED_TESTS -eq 0 ] && [ $WARNINGS -lt 3 ]; then
    echo ""
    echo "✓ Overall result: GOOD - Security measures applied with minimal impact"
    log_result ""
    log_result "OVERALL RESULT: GOOD - Security measures successful"
elif [ $FAILED_TESTS -lt 3 ]; then
    echo ""
    echo "⚠ Overall result: ACCEPTABLE - Some issues detected, review required"
    log_result ""
    log_result "OVERALL RESULT: ACCEPTABLE - Minor issues detected"
else
    echo ""
    echo "✗ Overall result: PROBLEMATIC - Significant functionality impact"
    log_result ""
    log_result "OVERALL RESULT: PROBLEMATIC - Significant functionality loss"
fi

echo ""
echo "Detailed results saved to: $RESULTS_FILE"
echo ""
echo "Recommendations:"
if [ $FAILED_TESTS -gt 0 ]; then
    echo "- Review failed tests and consider adjusting security measures"
fi
if [ $WARNINGS -gt 0 ]; then
    echo "- Investigate warnings to ensure security measures are fully effective"
fi
echo "- Run this test periodically to monitor ongoing functionality"
echo "- Compare results before/after security changes to measure impact"