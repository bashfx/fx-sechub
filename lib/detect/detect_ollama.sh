#!/bin/bash
# detect_ollama.sh - Detect Ollama server and usage
# Created: 2025-09-06

echo "=== Ollama Detection and Analysis ==="

# Check if Ollama is installed
if command -v ollama >/dev/null 2>&1; then
    echo "ALERT: Ollama is installed"
    ollama --version
else
    echo "Ollama not found in PATH"
fi

# Check if Ollama server is running
if pgrep -f "ollama" >/dev/null; then
    echo "ALERT: Ollama server is running"
    echo "Running processes:"
    ps aux | grep ollama | grep -v grep
    
    # Check resource usage
    echo "Resource usage:"
    top -bn1 | grep ollama | awk '{print "  CPU:", $9 "%, Memory:", $10 "%"}'
else
    echo "No Ollama processes detected"
fi

# Check for Ollama network connections
OLLAMA_CONNECTIONS=$(netstat -tupln 2>/dev/null | grep 11434)
if [ -n "$OLLAMA_CONNECTIONS" ]; then
    echo "ALERT: Ollama server listening on port 11434"
    echo "$OLLAMA_CONNECTIONS"
    
    # Check if exposed to network
    if echo "$OLLAMA_CONNECTIONS" | grep -q "0.0.0.0"; then
        echo "CRITICAL: Ollama exposed to network!"
    else
        echo "OK: Ollama bound to localhost only"
    fi
else
    echo "No network connections on port 11434"
fi

# Check disk usage from models
if [ -d ~/.ollama ]; then
    echo "Ollama directory found:"
    du -sh ~/.ollama 2>/dev/null || echo "  Cannot access ~/.ollama"
    
    if [ -d ~/.ollama/models ]; then
        MODEL_SIZE=$(du -sh ~/.ollama/models 2>/dev/null | cut -f1)
        MODEL_COUNT=$(find ~/.ollama/models -name "*.bin" 2>/dev/null | wc -l)
        echo "Models using: $MODEL_SIZE disk space ($MODEL_COUNT models)"
        
        # List recent models
        echo "Recently accessed models:"
        find ~/.ollama/models -name "*.bin" -type f -printf "%T+ %p\n" 2>/dev/null | \
            sort -r | head -5 | while read timestamp model; do
            echo "  $timestamp - $(basename $model)"
        done
    fi
else
    echo "No ~/.ollama directory found"
fi

# Check current Ollama API status
if curl -s --connect-timeout 2 http://localhost:11434/api/tags >/dev/null 2>&1; then
    echo "ALERT: Ollama API is responding"
    
    # Get model info
    MODELS=$(curl -s http://localhost:11434/api/tags | jq -r '.models[]?.name' 2>/dev/null)
    if [ -n "$MODELS" ]; then
        echo "Available models:"
        echo "$MODELS" | while read model; do
            echo "  - $model"
        done
    fi
    
    # Check running models
    RUNNING=$(curl -s http://localhost:11434/api/ps | jq -r '.models[]?.name' 2>/dev/null)
    if [ -n "$RUNNING" ]; then
        echo "Currently running:"
        echo "$RUNNING" | while read model; do
            echo "  - $model (active)"
        done
    fi
else
    echo "Ollama API not responding"
fi

echo ""
echo "=== Disk Space Analysis ==="
df -h / | awk 'NR==2 {print "Root filesystem:", $5, "used,", $4, "available"}'

# Calculate potential savings
if [ -d ~/.ollama/models ]; then
    POTENTIAL_SAVINGS=$(du -sh ~/.ollama/models 2>/dev/null | cut -f1)
    echo "Potential disk savings if Ollama models removed: $POTENTIAL_SAVINGS"
fi