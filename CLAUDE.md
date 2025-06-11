# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a Ruby-based prosodic text converter that analyzes audio files to extract prosodic patterns and converts text to SSML with natural speech timing. The application supports multiple pitch analysis backends and integrates with various LLM providers for intelligent text processing.

## Architecture

### Core Components

- **CLI Interface** (`lib/prosodic-text-converter/core/cli.rb`): Command-line interface with support for multiple pitch analysis backends
- **Converter Engine** (`lib/prosodic-text-converter/core/converter.rb`): Main conversion logic orchestrating audio analysis and text processing  
- **Pitch Analysis** (`lib/prosodic-text-converter/audio/pitch_analyzer.rb`): Factory pattern supporting Aubio and Sonic Annotator backends
- **Text Processing** (`lib/prosodic-text-converter/text/text_analyzer.rb`): Text analysis and chunking
- **SSML Generation** (`lib/prosodic-text-converter/conversion/ssml_formatter.rb`): Speech Synthesis Markup Language output

### Audio Analysis Pipeline

The application uses a two-backend system for pitch analysis:

1. **Aubio** (`:aubio`): Fast, accurate YIN algorithm - recommended for production use
2. **Sonic Annotator** (`:sonic_annotator`): Research-grade pYIN algorithm with comprehensive prosodic metrics

Backend selection is handled by `PitchAnalyzerFactory` which auto-detects available tools.

### Processing Flow

1. Audio file → Spectrogram generation (SoX)
2. Pitch analysis (Aubio or Sonic Annotator)  
3. Prosodic pattern extraction
4. Text analysis and chunking
5. LLM-based conversion with prosodic context
6. SSML output generation

## Development Commands

### Setup and Installation

```bash
# Initial setup with system dependencies
./setup.sh

# Install Ruby dependencies
bundle install

# Note: Transform files are now generated automatically by the Ruby application
```

### Testing and Quality

```bash
# Run RSpec tests (note: test suite may not be fully implemented yet)
bundle exec rspec

# Run RuboCop linting
bundle exec rubocop

# Auto-fix RuboCop issues
bundle exec rubocop -a
```

### Running the Application

```bash
# Main executable
./bin/prosodic-text-converter [options] [input_file]

# List available pitch analysis backends
./bin/prosodic-text-converter --list-backends

# Health check for dependencies
./bin/prosodic-text-converter --health-check

# Audio analysis with Aubio (fast)
./bin/prosodic-text-converter --audio=voice.wav --pitch-backend=aubio input.txt

# Research-grade analysis with Sonic Annotator
./bin/prosodic-text-converter --audio=voice.wav --pitch-backend=sonic_annotator input.txt

# Analysis only (no text conversion)
./bin/prosodic-text-converter --audio=voice.wav --analyze-only --verbose
```

## Key Dependencies

### System Requirements

- **SoX**: Audio processing and spectrogram generation
- **ImageMagick**: Image manipulation for spectrograms
- **Aubio**: Fast pitch analysis backend (recommended)
- **Sonic Annotator**: Research-grade analysis (optional)

### Ruby Gems

- `ruby_llm`: Multi-provider LLM interface (OpenAI, Anthropic, Ollama)
- `pragmatic_tokenizer`: Text tokenization
- `nokogiri`: XML/HTML processing
- `mini_magick`: ImageMagick interface

## Docker Usage

### Building and Running the Container

```bash
# Build the Docker image
docker build -t prosodic-text-converter .

# Run with help to see available options
docker run --rm prosodic-text-converter

# List available pitch analysis backends
docker run --rm prosodic-text-converter --list-backends

# Check container health and dependencies
docker run --rm prosodic-text-converter --health-check

# Verify Vamp plugins are available
docker run --rm prosodic-text-converter sonic-annotator -l
```

### Using with Audio Files and Text

```bash
# Create directories for input/output on host
mkdir -p ./input ./output ./spectrograms

# Copy your audio and text files to ./input/
cp voice_sample.wav input/
cp text_to_convert.txt input/

# Run audio analysis with Aubio backend
docker run --rm \
  -v $(pwd)/input:/app/input:ro \
  -v $(pwd)/output:/app/output \
  -v $(pwd)/spectrograms:/app/spectrograms \
  -e OPENAI_API_KEY="your-key-here" \
  prosodic-text-converter \
  --audio=/app/input/voice_sample.wav \
  --pitch-backend=aubio \
  /app/input/text_to_convert.txt

# Analysis only mode with Aubio (fast)
docker run --rm \
  -v $(pwd)/input:/app/input:ro \
  -v $(pwd)/spectrograms:/app/spectrograms \
  prosodic-text-converter \
  --audio=/app/input/voice_sample.wav \
  --pitch-backend=aubio \
  --analyze-only --verbose

# Research-grade analysis with Sonic Annotator
docker run --rm \
  -v $(pwd)/input:/app/input:ro \
  -v $(pwd)/spectrograms:/app/spectrograms \
  prosodic-text-converter \
  --audio=/app/input/voice_sample.wav \
  --pitch-backend=sonic_annotator \
  --analyze-only --verbose

# Pipe text input
echo "Hello, world!" | docker run --rm -i \
  -e ANTHROPIC_API_KEY="your-key-here" \
  prosodic-text-converter \
  --pattern=deliberate
```

### Docker Compose Example

```yaml
version: '3.8'
services:
  prosodic-converter:
    build: .
    volumes:
      - ./input:/app/input:ro
      - ./output:/app/output
      - ./spectrograms:/app/spectrograms
    environment:
      - OPENAI_API_KEY=${OPENAI_API_KEY}
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
      - PROSODIC_PITCH_BACKEND=aubio
    command: --help
```

### Advanced Docker Features

The container includes:
- **Health checks**: Automatic dependency verification
- **Non-root user**: Runs as `prosodic:prosodic` for security
- **Volume mounts**: Persistent input/output directories
- **Multi-stage build**: Optimized image size with separate builder stage
- **Both pitch backends**: Pre-installed Aubio and Sonic Annotator (built from source)
- **Complete Vamp plugin ecosystem**: 
  - pYIN plugin for probabilistic pitch tracking
  - Vamp example plugins (fixedtempo for rhythm analysis)
  - Aubio Vamp plugins for onset detection
  - Vamp SDK 2.10.0 for extensibility
- **Research-grade analysis**: Full Sonic Annotator 1.7 with comprehensive prosodic metrics

## Configuration

### Environment Variables

```bash
# LLM API keys (at least one required)
export OPENAI_API_KEY="your-key-here"
export ANTHROPIC_API_KEY="your-key-here"

# Optional: Default backend selection
export PROSODIC_PITCH_BACKEND="aubio"  # or "sonic_annotator"
```

### Backend Selection Guidelines

- **Use Aubio when**: Fast processing needed, production pipelines, speech applications
- **Use Sonic Annotator when**: Research applications, detailed prosodic analysis, academic work

### Transform Files

Sonic Annotator uses N3 transform files in the `transforms/` directory:
- `pyin_pitch.n3`: Main pitch tracking using pYIN algorithm
- `tempo.n3`: Rhythm and tempo analysis
- `fundamental_freq.n3`: Alternative F0 extraction
- `onset_detection.n3`: Note onset detection

Note: Transform files are now created entirely by the Ruby application when the SonicAnnotatorPitchAnalyzer is instantiated, eliminating the need for separate setup scripts.

## Known Issues and Backlog

Refer to `docs/PROSODIC_PIPELINE_BACKLOG.md` for detailed project roadmap. Key current issues:

1. **Docker containerization** - Multi-stage build with both Aubio and Sonic Annotator
2. **Duplicate Spectrogram classes** - Consolidate legacy and canonical implementations
3. **Test coverage** - RSpec test suite needs implementation
4. **Transform file management** - Automated N3 transform generation is implemented but could be optimized

## File Structure Notes

### Module Organization

The codebase follows a clear hierarchical structure:

- **Audio Processing**: `lib/prosodic-text-converter/audio/` - Spectrogram generation and pitch analysis
- **Analysis**: `lib/prosodic-text-converter/analysis/` - Pattern recognition and spectrogram analysis
- **Text Processing**: `lib/prosodic-text-converter/text/` - Text analysis and chunking
- **Conversion**: `lib/prosodic-text-converter/conversion/` - LLM integration and SSML formatting
- **Core**: `lib/prosodic-text-converter/core/` - CLI and main conversion orchestrator

### Duplicate Classes

There are currently two spectrogram generator classes:
- `lib/prosodic-text-converter/spectrogram.rb` (legacy)
- `lib/prosodic-text-converter/audio/spectrogram.rb` (canonical)

The canonical version in the `audio/` directory should be preferred.

## Testing Strategy

Tests should focus on:
- Backend availability detection
- Audio analysis pipeline with both backends
- LLM integration with multiple providers
- SSML output validation
- Error handling for missing dependencies

## Development Guidance

### Code Style
- Include YARD documentation comments for all public methods
- Use factory patterns for backend selection (see `PitchAnalyzerFactory`)
- Follow Ruby naming conventions and module organization
- Work on one class at a time to maintain focus

### Error Handling
- All external tool dependencies should be gracefully handled
- Include comprehensive logging throughout the pipeline
- Use appropriate exception types for different failure modes
- Validate input files before processing

### Audio Backend Integration
- Use the factory pattern to support multiple pitch analysis backends
- Detect available tools at runtime rather than hardcoding dependencies
- Provide fallback mechanisms when preferred backends are unavailable