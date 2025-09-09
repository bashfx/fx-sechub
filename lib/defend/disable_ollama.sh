#!/bin/bash
# disable_ollama.sh - Completely disable Ollama integration
# Created: 2025-09-06

echo "=== Ollama Complete Disablement ==="

# Show current state first
echo "Current Ollama status:"
if pgrep -f "ollama" >/dev/null; then
    echo "  ✗ Ollama is currently running"
    ps aux | grep ollama | grep -v grep | awk '{print "    PID:", $2, "CMD:", $11}'
else
    echo "  ✓ Ollama is not running"
fi

if [ -d ~/.ollama ]; then
    OLLAMA_SIZE=$(du -sh ~/.ollama 2>/dev/null | cut -f1)
    echo "  ✗ Ollama directory exists: $OLLAMA_SIZE"
else
    echo "  ✓ No Ollama directory found"
fi

if netstat -tupln 2>/dev/null | grep -q 11434; then
    echo "  ✗ Port 11434 is in use"
else
    echo "  ✓ Port 11434 is free"
fi

echo ""

# Confirm action
read -p "Proceed with complete Ollama disablement? This will stop services and can free significant disk space. (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 0
fi

echo "Disabling Ollama integration..."

# Stop Ollama server
echo "1. Stopping Ollama processes..."
if pgrep -f "ollama" >/dev/null; then
    pkill -f ollama
    echo "   ✓ Ollama processes terminated"
    
    # Wait for graceful shutdown
    sleep 2
    
    # Force kill if still running
    if pgrep -f "ollama" >/dev/null; then
        pkill -9 -f ollama
        echo "   ✓ Force-killed remaining Ollama processes"
    fi
else
    echo "   ✓ No Ollama processes to stop"
fi

# Disable Ollama systemd service (if exists)
echo "2. Disabling Ollama system service..."
if systemctl list-units --full -all | grep -q ollama; then
    sudo systemctl stop ollama 2>/dev/null && echo "   ✓ Stopped ollama service"
    sudo systemctl disable ollama 2>/dev/null && echo "   ✓ Disabled ollama service"
else
    echo "   ✓ No system service found"
fi

# Block Ollama network port
echo "3. Blocking Ollama network access..."
if [ "$EUID" -ne 0 ]; then
    echo "   Note: Run with sudo to apply firewall rules"
    SUDO_PREFIX="sudo"
else
    SUDO_PREFIX=""
fi

$SUDO_PREFIX iptables -A INPUT -p tcp --dport 11434 -j DROP 2>/dev/null
$SUDO_PREFIX iptables -A OUTPUT -p tcp --dport 11434 -j DROP 2>/dev/null
echo "   ✓ Network access blocked (port 11434)"

# Handle model removal
if [ -d ~/.ollama ]; then
    echo ""
    echo "4. Ollama models and data:"
    
    if [ -d ~/.ollama/models ]; then
        MODEL_SIZE=$(du -sh ~/.ollama/models 2>/dev/null | cut -f1)
        MODEL_COUNT=$(find ~/.ollama/models -name "*.bin" 2>/dev/null | wc -l)
        echo "   Found $MODEL_COUNT models using $MODEL_SIZE"
        
        # Show model details
        echo "   Model details:"
        find ~/.ollama/models -name "*.bin" -type f -printf "     %s bytes - %p\n" 2>/dev/null | \
            head -10 | while read size path; do
            size_mb=$(( size / 1024 / 1024 ))
            echo "     ${size_mb}MB - $(basename $path)"
        done
        
        echo ""
        read -p "   Remove all Ollama models to free $MODEL_SIZE disk space? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf ~/.ollama/models/
            echo "   ✓ Models removed, $MODEL_SIZE disk space freed"
        else
            echo "   - Models kept (use 'rm -rf ~/.ollama/models/' to remove later)"
        fi
    fi
    
    # Remove other Ollama data
    read -p "   Remove all Ollama configuration and logs? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf ~/.ollama/
        echo "   ✓ All Ollama data removed"
    else
        echo "   - Configuration kept"
    fi
else
    echo "4. ✓ No Ollama directory to clean up"
fi

# Block model downloads
echo ""
echo "5. Blocking model download sources..."
$SUDO_PREFIX iptables -A OUTPUT -d registry.ollama.ai -j DROP 2>/dev/null
$SUDO_PREFIX iptables -A OUTPUT -d huggingface.co -j DROP 2>/dev/null
echo "   ✓ Blocked access to model registries"

# Remove Ollama from PATH (if installed via binary)
echo ""
echo "6. Checking Ollama installation..."
if command -v ollama >/dev/null 2>&1; then
    OLLAMA_PATH=$(which ollama)
    echo "   Found Ollama binary at: $OLLAMA_PATH"
    
    read -p "   Remove Ollama binary? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [[ "$OLLAMA_PATH" == /usr/local/bin/* ]] || [[ "$OLLAMA_PATH" == /opt/* ]]; then
            sudo rm -f "$OLLAMA_PATH"
            echo "   ✓ Ollama binary removed"
        else
            echo "   ✗ Cannot remove Ollama from $OLLAMA_PATH (manual removal required)"
        fi
    else
        echo "   - Ollama binary kept"
    fi
else
    echo "   ✓ No Ollama binary in PATH"
fi

echo ""
echo "=== Ollama Disablement Complete ==="
echo ""

# Show final state
echo "Final status:"
if pgrep -f "ollama" >/dev/null; then
    echo "  ✗ WARNING: Some Ollama processes still running"
else
    echo "  ✓ No Ollama processes running"
fi

if [ -d ~/.ollama ]; then
    REMAINING_SIZE=$(du -sh ~/.ollama 2>/dev/null | cut -f1)
    echo "  - Ollama directory remains: $REMAINING_SIZE"
else
    echo "  ✓ Ollama directory removed"
fi

if netstat -tupln 2>/dev/null | grep -q 11434; then
    echo "  ✗ WARNING: Port 11434 still in use"
else
    echo "  ✓ Port 11434 is free"
fi

# Show disk space recovery
echo ""
echo "Disk space status:"
df -h / | awk 'NR==2 {print "  Root filesystem:", $5, "used,", $4, "available"}'

echo ""
echo "To re-enable Ollama later:"
echo "  1. Remove firewall rules: sudo iptables -D OUTPUT -p tcp --dport 11434 -j DROP"
echo "  2. Reinstall Ollama: curl -fsSL https://ollama.ai/install.sh | sh"
echo "  3. Start service: ollama serve"
echo ""
echo "IMPORTANT: Test OpenAI Codex to ensure --oss flag no longer works:"
echo "  codex --oss 'test command'  # Should fail or fallback to cloud"