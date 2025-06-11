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

# --- System Dependencies ---

echo "📦 Installing system dependencies..."

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux (Debian/Ubuntu)
    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y sox imagemagick ruby ruby-dev build-essential aubio-tools
        
        # Optional: sonic-annotator (research-grade analysis)
        echo "ℹ️  For research-grade pitch analysis, you can also install sonic-annotator:"
        echo "   Download from: https://vamp-plugins.org/sonic-annotator/"
        
    elif command -v yum &> /dev/null; then
        # RHEL/CentOS
        sudo yum install -y sox ImageMagick ruby ruby-devel gcc aubio
    else
        echo "❌ Unsupported Linux distribution. Please install sox, imagemagick, aubio, and ruby manually."
        exit 1
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    if command -v brew &> /dev/null; then
        brew install sox imagemagick ruby aubio
        
        # Optional: sonic-annotator
        echo "ℹ️  For research-grade pitch analysis, you can also install sonic-annotator:"
        echo "   brew install sonic-visualiser  # includes sonic-annotator"
        
    else
        echo "❌ Homebrew not found. Please install Homebrew first:"
        echo "   /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi
else
    echo "❌ Unsupported operating system: $OSTYPE"
    exit 1
fi

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
if [ -f "prosodic_converter.rb" ]; then
    chmod +x prosodic_converter.rb
    echo "✅ Made prosodic_converter.rb executable"
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
if ruby -c prosodic_converter.rb &> /dev/null; then
    echo "✅ Ruby script syntax is valid"
else
    echo "❌ Ruby script has syntax errors"
    exit 1
fi

# Test pitch analysis backends
if [ -f "prosodic_converter.rb" ]; then
    echo "🎤 Testing pitch analysis backends..."
    if ruby prosodic_converter.rb --list-backends &> /dev/null; then
        echo "✅ Pitch backend detection working"
        echo "Available backends:"
        ruby prosodic_converter.rb --list-backends | grep "✓"
    else
        echo "⚠️  Backend detection test failed"
    fi
fi

# Test basic functionality (if API key is available)
if [ -n "$OPENAI_API_KEY" ] || [ -n "$ANTHROPIC_API_KEY" ]; then
    echo "🔑 API key found - testing basic conversion..."
    if echo "Hello world" | ruby prosodic_converter.rb &> /dev/null; then
        echo "✅ Basic text conversion working"
    else
        echo "⚠️  Basic conversion test failed - check API key and network"
    fi
else
    echo "ℹ️  No API key found - skipping live conversion test"
    echo "   Set OPENAI_API_KEY or ANTHROPIC_API_KEY to enable LLM features"
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
echo "1. Set your LLM API key:"
echo "   export OPENAI_API_KEY='your-key-here'"
echo "   # OR"
echo "   export ANTHROPIC_API_KEY='your-key-here'"
echo ""
echo "2. Test basic conversion:"
echo "   echo 'Hello, world!' | ./prosodic_converter.rb"
echo ""
echo "3. List available pitch backends:"
echo "   ./prosodic_converter.rb --list-backends"
echo ""
echo "4. Test audio analysis (requires audio file):"
echo "   ./prosodic_converter.rb --audio=sample.wav --analyze-only"
echo ""
echo "5. Test with specific backend:"
if [[ "$AUBIO_AVAILABLE" == true ]]; then
    echo "   ./prosodic_converter.rb --audio=voice.wav --pitch-backend=aubio text.txt"
fi
if [[ "$SONIC_AVAILABLE" == true ]]; then
    echo "   ./prosodic_converter.rb --audio=voice.wav --pitch-backend=sonic_annotator text.txt"
fi
echo ""
echo "6. Full pipeline test:"
echo "   ./prosodic_converter.rb --audio=voice.wav text.txt > output.ssml"
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
    echo "📝 To install Sonic Annotator (optional, for research):"
    echo "   Download from: https://vamp-plugins.org/sonic-annotator/"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "   # OR with Homebrew:"
        echo "   brew install sonic-visualiser"
    fi
    echo ""
fi

echo "📖 See gemfile_and_usage.rb for advanced backend selection examples"
echo ""
echo "🎉 Happy prosodic converting!"