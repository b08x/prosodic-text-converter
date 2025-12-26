#!/bin/bash

# ==============================================================================
#
# setup.sh - Setup script for Prosodic Text Converter
#
# Description:
#   Installs and configures all dependencies for the Ruby prosodic text 
#   converter application, including audio analysis capabilities with
#   multiple pitch analysis backends.
#
# Author:
#   Assistant
#
# ==============================================================================

set -e  # Exit on any error

echo "🎵 Setting up Prosodic Text Converter..."

# --- Environment Setup ---

mkdir -p "$HOME/.local/bin"
mkdir -p "lib/vamp/plugins"
mkdir -p "lib/vamp/transforms"

# Set VAMP_PATH to include our local project plugins
PROJECT_VAMP_PATH="$(pwd)/lib/vamp/plugins"
export VAMP_PATH="$PROJECT_VAMP_PATH:${VAMP_PATH:-/usr/local/lib/vamp:/usr/lib/vamp}"

# Add local bin to PATH for the current session if not already there
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    export PATH="$HOME/.local/bin:$PATH"
fi

# --- Functions ---

install_sonic_annotator() {
    echo "📥 Installing sonic-annotator to ~/.local/bin..."
    SONIC_VERSION="1.7"
    SONIC_URL="https://github.com/sonic-visualiser/sonic-annotator/releases/download/sonic-annotator-${SONIC_VERSION}/sonic-annotator-${SONIC_VERSION}.0-linux64-static.tar.gz"
    
    TMP_DIR=$(mktemp -d)
    curl -L "$SONIC_URL" -o "$TMP_DIR/sonic-annotator.tar.gz"
    tar -xzf "$TMP_DIR/sonic-annotator.tar.gz" -C "$TMP_DIR"
    cp "$TMP_DIR/sonic-annotator-${SONIC_VERSION}.0-linux64-static/sonic-annotator" "$HOME/.local/bin/"
    chmod +x "$HOME/.local/bin/sonic-annotator"
    
    rm -rf "$TMP_DIR"
    echo "✅ sonic-annotator installed successfully"
}

install_vamp_plugins() {
    echo "📥 Installing Vamp plugins to lib/vamp/plugins..."
    VAMP_DIR="lib/vamp/plugins"
    mkdir -p "$VAMP_DIR"
    TMP_DIR=$(mktemp -d)

    # 1. pYIN plugin
    echo "   - pYIN plugin"
    curl -L "https://code.soundsoftware.ac.uk/attachments/download/2631/pyin-v1.2-linux64.tar.gz" -o "$TMP_DIR/pyin.tar.gz"
    tar -xzf "$TMP_DIR/pyin.tar.gz" -C "$TMP_DIR"
    cp "$TMP_DIR/pyin-v1.2-linux64/pyin.so" "$VAMP_DIR/"

    # 2. Vamp SDK Examples
    echo "   - Vamp SDK examples"
    curl -L "https://code.soundsoftware.ac.uk/attachments/download/2693/vamp-plugin-sdk-2.10.0-binaries-amd64-linux.tar.gz" -o "$TMP_DIR/vamp-sdk.tar.gz"
    tar -xzf "$TMP_DIR/vamp-sdk.tar.gz" -C "$TMP_DIR"
    find "$TMP_DIR/vamp-plugin-sdk-2.10.0-binaries-amd64-linux" -name "*.so" -exec cp {} "$VAMP_DIR/" \;

    # 3. Aubio Vamp plugins
    echo "   - Aubio Vamp plugins"
    curl -L "https://aubio.org/bin/vamp-aubio-plugins/0.5.1/vamp-aubio-plugins-0.5.1-x86_64.tar.bz2" -o "$TMP_DIR/aubio-vamp.tar.bz2"
    tar -xjf "$TMP_DIR/aubio-vamp.tar.bz2" -C "$TMP_DIR"
    cp "$TMP_DIR/vamp-aubio-plugins-0.5.1-x86_64/"*.so "$VAMP_DIR/"

    rm -rf "$TMP_DIR"
    echo "✅ Vamp plugins installed successfully in lib/vamp/plugins"
}

# --- System Dependencies ---

echo "📦 Installing system dependencies..."

case "$OSTYPE" in
    linux-gnu*)
        if command -v apt-get &> /dev/null; then
            # Debian/Ubuntu
            sudo apt-get update
            sudo apt-get install -y sox imagemagick ruby ruby-dev build-essential aubio-tools
        elif command -v pacman &> /dev/null; then
            # Arch Linux
            sudo pacman -Sy --needed sox imagemagick ruby aubio
        elif command -v yum &> /dev/null; then
            # RHEL/CentOS
            sudo yum install -y sox ImageMagick ruby ruby-devel gcc aubio
        else
            echo "❌ Unsupported Linux distribution. Please install sox, imagemagick, aubio, and ruby manually."
            exit 1
        fi
        ;;
    darwin*)
        # macOS
        if command -v brew &> /dev/null; then
            brew install sox imagemagick ruby aubio
        else
            echo "❌ Homebrew not found. Please install Homebrew first:"
            echo "   /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            exit 1
        fi
        ;;
    *)
        echo "❌ Unsupported operating system: $OSTYPE"
        exit 1
        ;;
esac

# --- Verify Dependencies ---

echo "🔍 Verifying system dependencies..."

if ! command -v sox &> /dev/null; then
    echo "❌ SoX not found in PATH"
    exit 1
fi

if ! command -v convert &> /dev/null; then
    echo "❌ ImageMagick not found in PATH"
    exit 1
fi

if ! command -v ruby &> /dev/null; then
    echo "❌ Ruby not found in PATH"
    exit 1
fi

echo "✅ Core dependencies verified"

# --- Verify Pitch Analysis Backends ---

echo "🎤 Checking pitch analysis backends..."

AUBIO_AVAILABLE=false
SONIC_AVAILABLE=false

if command -v aubio &> /dev/null; then
    AUBIO_AVAILABLE=true
    echo "✅ Aubio found - fast, accurate pitch analysis"
else
    echo "⚠️  Aubio not found - install for best performance"
fi

if command -v sonic-annotator &> /dev/null; then
    SONIC_AVAILABLE=true
    echo "✅ Sonic Annotator found - research-grade analysis"
else
    echo "ℹ️  Sonic Annotator not found - optional for advanced analysis"
    if [[ "$OSTYPE" == linux-gnu* ]]; then
        read -p "❓ Would you like to install sonic-annotator and common Vamp plugins to ~/.local? [y/N] " install_sonic
        if [[ "$install_sonic" =~ ^[Yy]$ ]]; then
            install_sonic_annotator
            install_vamp_plugins
            SONIC_AVAILABLE=true
        fi
    fi
fi

if [[ "$AUBIO_AVAILABLE" == false && "$SONIC_AVAILABLE" == false ]]; then
    echo "❌ No pitch analysis backends found"
    echo "   Install aubio for basic functionality or sonic-annotator for advanced features"
    exit 1
fi

# --- Ruby Dependencies ---

echo "💎 Installing Ruby gems..."

if ! command -v bundler &> /dev/null; then
    gem install bundler
fi

bundle install

echo "✅ Ruby gems installed"

# --- Setup Scripts ---

echo "🔧 Setting up scripts..."

# Note: Spectrogram generation is now handled directly by Ruby/FFmpeg integration
echo "ℹ️  Spectrogram generation integrated into Ruby application"

# Make the main script executable
if [ -f "bin/prosodic-text-converter" ]; then
    chmod +x bin/prosodic-text-converter
    echo "✅ Made bin/prosodic-text-converter executable"
fi

# Create output directories
mkdir -p spectrograms
mkdir -p output
echo "✅ Created output directories"

# --- Test Installation ---

echo "🧪 Testing installation..."

# Test SoX with a simple command
if sox --version &> /dev/null; then
    echo "✅ SoX is working"
else
    echo "❌ SoX test failed"
    exit 1
fi

# Test Ruby script syntax
if [ -f "bin/prosodic-text-converter" ]; then
    if ruby -c bin/prosodic-text-converter &> /dev/null; then
        echo "✅ Ruby script syntax is valid"
    else
        echo "❌ Ruby script has syntax errors"
        ruby -c bin/prosodic-text-converter
        exit 1
    fi
else
    echo "⚠️  bin/prosodic-text-converter not found, skipping syntax check"
fi

# Test pitch analysis backends
if [ -f "bin/prosodic-text-converter" ]; then
    echo "🎤 Testing pitch analysis backends..."
    if ruby bin/prosodic-text-converter --list-backends &> /dev/null; then
        echo "✅ Pitch backend detection working"
        echo "Available backends:"
        ruby bin/prosodic-text-converter --list-backends | grep "✓"
    else
        echo "⚠️  Backend detection test failed"
    fi
fi

# Test basic functionality (if API key is available)
if [ -n "$OPENAI_API_KEY" ] || [ -n "$ANTHROPIC_API_KEY" ] || [ -n "$GEMINI_API_KEY" ]; then
    echo "🔑 API key found - testing basic conversion..."
    if echo "Hello world" | ruby bin/prosodic-text-converter &> /dev/null; then
        echo "✅ Basic text conversion working"
    else
        echo "⚠️  Basic conversion test failed - check API key and network"
    fi
else
    echo "ℹ️  No API key found - skipping live conversion test"
    echo "   Copy .env.example to .env and add your API keys to enable LLM features"
fi

# --- Configuration Suggestions ---

echo ""
echo "🎯 Setup Complete!"
echo ""
echo "Pitch Analysis Backends:"
if [[ "$AUBIO_AVAILABLE" == true ]]; then
    echo "✅ Aubio - Fast, accurate, recommended for most use cases"
fi
if [[ "$SONIC_AVAILABLE" == true ]]; then
    echo "✅ Sonic Annotator - Research-grade, advanced plugin ecosystem"
fi
echo ""
echo "Next steps:"
echo "1. Configure your LLM API keys:"
echo "   cp .env.example .env"
echo "   # Edit .env and add your actual API keys"
echo ""
echo "2. Test basic conversion:"
echo "   echo 'Hello, world!' | ./bin/prosodic-text-converter"
echo ""
echo "3. List available pitch backends:"
echo "   ./bin/prosodic-text-converter --list-backends"
echo ""
echo "4. Test audio analysis (requires audio file):"
echo "   ./bin/prosodic-text-converter --audio=sample.wav --analyze-only"
echo ""
echo "5. Test with specific backend:"
if [[ "$AUBIO_AVAILABLE" == true ]]; then
    echo "   ./bin/prosodic-text-converter --audio=voice.wav --pitch-backend=aubio text.txt"
fi
if [[ "$SONIC_AVAILABLE" == true ]]; then
    echo "   ./bin/prosodic-text-converter --audio=voice.wav --pitch-backend=sonic_annotator text.txt"
fi
echo ""
echo "6. Full pipeline test:"
echo "   ./bin/prosodic-text-converter --audio=voice.wav text.txt > output.ssml"
echo ""

# Show backend-specific installation tips
if [[ "$AUBIO_AVAILABLE" == false ]]; then
    echo "📝 To install Aubio (recommended):"
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "   sudo apt-get install aubio-tools"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "   brew install aubio"
    fi
    echo ""
fi

if [[ "$SONIC_AVAILABLE" == false ]]; then
    echo "📝 To install sonic-annotator and Vamp plugins:"
    echo "   # You can run these functions directly if needed, or re-run setup.sh"
    echo "   # to trigger the interactive prompt."
    echo "   # sonic-annotator will be in ~/.local/bin"
    echo "   # Plugins will be in lib/vamp/plugins"
    echo ""
fi

echo "📖 See gemfile_and_usage.rb for advanced backend selection examples"
echo ""
echo "🎉 Happy prosodic converting!"