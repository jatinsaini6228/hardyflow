#!/usr/bin/env bash
# ==============================================================================
# HardyFlow Local AI (Llama 3) Setup Helper
# ==============================================================================
# This script sets up or checks for a local Llama 3 server on macOS.
# ==============================================================================

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${PROJECT_DIR}/.env"

echo "🤖 [HardyFlow] Checking Local AI & Llama 3 Environment..."

# 1. Check if Ollama is installed
if command -v ollama >/dev/null 2>&1; then
    echo "✅ Ollama is installed on your Mac!"
    echo "🚀 Pulling / verifying Llama 3.2 model..."
    ollama pull llama3.2 || ollama pull llama3
    
    echo "📝 Configuring ${ENV_FILE} to use local Ollama..."
    cat << 'EOF' > "${ENV_FILE}"
# HardyFlow Local Ollama Configuration (100% Offline & Free)
LLAMA_API_KEY=local-no-key-required
LLAMA_API_URL=http://localhost:11434/v1/chat/completions
LLAMA_MODEL=llama3.2
LLAMA_TEMPERATURE=0.3
EOF
    echo "✨ Configured for local Ollama!"
    echo "To start Ollama server in background if not already running: ollama serve &"
    exit 0
fi

# 2. Check if Homebrew is available to install Ollama
if command -v brew >/dev/null 2>&1; then
    echo "💡 Homebrew detected. You can install Ollama by running:"
    echo "   brew install ollama"
    echo "   ollama pull llama3.2"
fi

echo "------------------------------------------------------------------"
echo "💡 Alternatively, you can use Groq Cloud for instant, free Llama 3:"
echo "   1. Get a free API key at https://console.groq.com/keys"
echo "   2. Open ${ENV_FILE}"
echo "   3. Set: LLAMA_API_KEY=gsk_your_key_here"
echo "------------------------------------------------------------------"
