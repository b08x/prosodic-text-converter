# Prosodic Text Converter

A Ruby-based prosodic text converter that analyzes audio files to extract prosodic patterns and converts text to SSML (Speech Synthesis Markup Language) with natural speech timing. The application integrates sophisticated pitch analysis backends with AI-powered language models to produce intelligent prosodic markup.

## Features

- **Dual-Backend Audio Analysis**: Choose between Aubio (fast, production-ready) and Sonic Annotator (research-grade)
- **Advanced Text Analysis**: Uses lingua and pragmatic_tokenizer for sophisticated linguistic preprocessing
- **AI-Powered Prosodic Decisions**: Integrates with multiple LLM providers (OpenAI, Anthropic, Google Gemini)
- **Intelligent SSML Generation**: Produces natural-sounding speech markup with proper timing and pitch variation
- **🆕 Speech Pattern Extraction**: Analyze spectrograms to extract comprehensive speech patterns including rhythm, stress, and intonation
- **🆕 Pattern-Based Text Rewriting**: Intelligently rewrite input text to better match extracted speech patterns using SFL principles
- **🆕 Multi-Strategy Optimization**: Choose from rhythm, stress, intonation, hybrid, or comprehensive rewriting approaches
- **🆕 Iterative Refinement**: Apply multiple rounds of intelligent text optimization with meaning preservation
- **Docker Support**: Fully containerized with multi-stage builds and security best practices
- **Comprehensive Logging**: Detailed analysis and conversion tracking

## Quick Start

### Prerequisites

- Ruby 3.1+
- SoX (audio processing)
- ImageMagick (spectrogram generation)
- Aubio tools (recommended) or Sonic Annotator (optional)
- At least one LLM provider API key

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd prosodic-text-converter

# Install dependencies
./setup.sh

# Install Ruby gems
bundle install

# Configure API keys
cp .env.example .env
# Edit .env and add your actual API keys
```

### Basic Usage

```bash
# Simple text conversion with predefined pattern
echo "Hello world! This is a test." | ./bin/prosodic-text-converter --pattern=deliberate

# Convert text using audio-extracted prosodic pattern
./bin/prosodic-text-converter --audio=voice_sample.wav --provider=gemini text.txt

# 🆕 Convert with speech pattern analysis and text rewriting
./bin/prosodic-text-converter --audio=voice.wav --enable-speech-patterns --enable-pattern-rewriting text.txt

# 🆕 Advanced pattern-based rewriting with custom strategy
./bin/prosodic-text-converter --audio=voice.wav --enable-pattern-rewriting --rewrite-strategy=rhythm --pattern-rewrite-aggressiveness=aggressive text.txt

# Analysis-only mode to examine audio prosodic features
./bin/prosodic-text-converter --audio=speaker.wav --analyze-only --verbose
```

## Architecture

### Core Components

- **CLI Interface** (`lib/prosodic-text-converter/core/cli.rb`): Command-line interface with comprehensive option parsing
- **Converter Engine** (`lib/prosodic-text-converter/core/converter.rb`): Main orchestrator for audio analysis and text processing
- **Text Analyzer** (`lib/prosodic-text-converter/text/text_analyzer.rb`): Linguistic preprocessing using lingua and pragmatic_tokenizer
- **LLM Converter** (`lib/prosodic-text-converter/conversion/llm_converter.rb`): AI-powered prosodic decision making
- **Pitch Analysis** (`lib/prosodic-text-converter/audio/pitch_analyzer.rb`): Factory pattern supporting multiple backends
- **SSML Formatter** (`lib/prosodic-text-converter/conversion/ssml_formatter.rb`): Output validation and formatting
- **🆕 Speech Pattern Extractor** (`lib/prosodic-text-converter/analysis/speech_pattern_extractor.rb`): Advanced spectrogram analysis for rhythm, stress, and intonation patterns
- **🆕 Speech Pattern Rewriter** (`lib/prosodic-text-converter/text/speech_pattern_rewriter.rb`): Intelligent text rewriting using SFL principles and extracted speech patterns

### Processing Pipeline

1. **Audio Analysis** (optional): Extract prosodic patterns from reference audio
2. **🆕 Speech Pattern Extraction** (optional): Analyze spectrograms for comprehensive speech patterns including emotional markers
3. **Text Preprocessing**: Sentence segmentation, tokenization, and linguistic analysis
4. **🆕 Pattern-Based Text Rewriting** (optional): Intelligently rewrite text to match extracted speech patterns
5. **LLM Processing**: Generate prosodic markup based on linguistic context and audio patterns
6. **SSML Generation**: Validate and format final Speech Synthesis Markup Language output

## Usage Examples

### Predefined Patterns

Choose from built-in prosodic patterns optimized for different speaking styles:

```bash
# Deliberate speaking (1.0s segments, 350ms pauses)
./bin/prosodic-text-converter --pattern=deliberate --provider=openai input.txt

# Rapid speaking (0.6s segments, 200ms pauses)
./bin/prosodic-text-converter --pattern=rapid --provider=anthropic input.txt

# Contemplative speaking (1.4s segments, 500ms pauses)
./bin/prosodic-text-converter --pattern=contemplative --provider=gemini input.txt
```

### Audio-Guided Conversion

Extract prosodic patterns from audio for personalized speech timing:

```bash
# Fast analysis with Aubio (recommended)
./bin/prosodic-text-converter --audio=voice.wav --pitch-backend=aubio input.txt

# Research-grade analysis with Sonic Annotator
./bin/prosodic-text-converter --audio=voice.wav --pitch-backend=sonic_annotator input.txt

# Analyze multiple audio files
for file in *.wav; do
  ./bin/prosodic-text-converter --audio="$file" --analyze-only --verbose > "${file%.wav}_analysis.txt"
done
```

### 🆕 Advanced Speech Pattern Analysis

Extract comprehensive speech patterns from spectrograms for intelligent text rewriting:

```bash
# Enable speech pattern extraction and text rewriting
./bin/prosodic-text-converter --audio=voice.wav \
  --enable-speech-patterns \
  --enable-pattern-rewriting \
  --rewrite-strategy=hybrid \
  input.txt

# Focus on specific speech aspects
./bin/prosodic-text-converter --audio=voice.wav \
  --enable-pattern-rewriting \
  --rewrite-strategy=rhythm \
  --rhythm-sensitivity=0.8 \
  input.txt

# Aggressive rewriting with iterative refinement
./bin/prosodic-text-converter --audio=voice.wav \
  --enable-pattern-rewriting \
  --rewrite-strategy=comprehensive \
  --pattern-rewrite-aggressiveness=aggressive \
  --max-rewrite-iterations=5 \
  --pattern-meaning-threshold=0.9 \
  input.txt

# Analyze speech patterns without text rewriting
./bin/prosodic-text-converter --audio=voice.wav \
  --enable-speech-patterns \
  --disable-pattern-rewriting \
  --enable-emotional-detection \
  --analyze-only \
  input.txt

# Custom pattern analysis settings
./bin/prosodic-text-converter --audio=voice.wav \
  --enable-speech-patterns \
  --enable-pattern-rewriting \
  --stress-threshold=0.7 \
  --intonation-smoothing=0.4 \
  --enable-iterative-refinement \
  input.txt
```

#### Available Rewrite Strategies

- **`rhythm`**: Focus on optimizing temporal patterns and timing
- **`stress`**: Emphasize stress patterns and syllable prominence
- **`intonation`**: Optimize for pitch contours and boundary tones
- **`hybrid`**: Balance rhythm and stress considerations
- **`comprehensive`**: Consider all speech pattern dimensions

#### Pattern Analysis Features

- **Rhythm Analysis**: Onset intervals, tempo variations, rhythmic groupings
- **Stress Detection**: Primary/secondary stress patterns, stress density
- **Intonation Mapping**: Pitch contours, boundary tones, phrase-level prosody
- **Emotional Detection**: Arousal/valence analysis from spectral features
- **Breathing Patterns**: Breath pause detection and respiratory rhythm

### LLM Provider Configuration

Support for multiple AI providers via environment variables configured in your `.env` file:

```bash
# Add API keys to your .env file (copy from .env.example)
# OPENAI_API_KEY=your-key-here
# ANTHROPIC_API_KEY=your-key-here  
# GEMINI_API_KEY=your-key-here

# OpenAI (GPT models)
./bin/prosodic-text-converter --provider=openai --model=gpt-4 input.txt

# Anthropic (Claude models)
./bin/prosodic-text-converter --provider=anthropic --model=claude-3-sonnet input.txt

# Google Gemini
./bin/prosodic-text-converter --provider=gemini --model=gemini-2.5-flash input.txt
```

## Docker Usage

### Quick Start with Docker

```bash
# Build the container
docker build -t prosodic-text-converter .

# Run with help
docker run --rm prosodic-text-converter --help

# Check available backends
docker run --rm prosodic-text-converter --list-backends

# Verify container health
docker run --rm prosodic-text-converter --health-check
```

### Processing Files with Docker

```bash
# Set up directories
mkdir -p ./input ./output ./spectrograms

# Copy your files
cp voice_sample.wav input/
cp document.txt input/

# Run conversion with audio analysis
docker run --rm \
  -v $(pwd)/input:/app/input:ro \
  -v $(pwd)/output:/app/output \
  -v $(pwd)/spectrograms:/app/spectrograms \
  -e GEMINI_API_KEY="your-key-here" \
  prosodic-text-converter \
  --audio=/app/input/voice_sample.wav \
  --pitch-backend=aubio \
  /app/input/document.txt > output/document.ssml
```

### Docker Compose

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
      - GEMINI_API_KEY=${GEMINI_API_KEY}
      - PROSODIC_PITCH_BACKEND=aubio
    command: ["--audio=/app/input/voice.wav", "/app/input/text.txt"]
```

## Backend Comparison

### Aubio Backend (Recommended)

**Best for**: Production pipelines, real-time processing, speech applications

- **Algorithm**: YIN pitch detection
- **Speed**: Very fast (~0.4s for typical audio)
- **Accuracy**: High for speech analysis
- **Dependencies**: Minimal (aubio-tools package)
- **Use cases**: Voice cloning, podcast processing, speech synthesis

### Sonic Annotator Backend (Research-Grade)

**Best for**: Academic research, detailed analysis, music processing

- **Algorithm**: pYIN (probabilistic YIN)
- **Speed**: Slower (~2-3s for typical audio)
- **Accuracy**: Highest precision with uncertainty measures
- **Dependencies**: Qt6, Vamp plugins, complex build process
- **Use cases**: Phonetic research, music analysis, detailed prosodic studies

## Command Reference

### Basic Options

```bash
--pattern=NAME          # Use predefined pattern (deliberate, rapid, contemplative)
--audio=FILE           # Extract prosodic pattern from audio file
--pitch-backend=NAME   # Pitch analysis backend (aubio, sonic_annotator)
--provider=NAME        # LLM provider (openai, anthropic, gemini, ollama)
--model=NAME           # Model name (gpt-4, claude-3-sonnet, gemini-2.5-flash)
--verbose              # Show detailed analysis information
--analyze-only         # Only analyze audio, don't convert text
--list-backends        # Show available pitch analysis backends
--health-check         # Verify all dependencies are working
```

### Advanced Options

```bash
--spectrogram-dir=DIR  # Output directory for spectrograms (default: ./spectrograms)
```

### Input Methods

```bash
# File input
./bin/prosodic-text-converter input.txt

# Stdin input
echo "Text to convert" | ./bin/prosodic-text-converter

# Combined with audio analysis
./bin/prosodic-text-converter --audio=voice.wav input.txt
```

## Output Format

The application outputs SSML (Speech Synthesis Markup Language) to stdout:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<speak>
  <prosody rate="medium" pitch="+3%">Hello world!</prosody>
  <break time="350ms"/>
  <prosody rate="medium" pitch="-2%">This is a test.</prosody>
</speak>
```

### SSML Features

- **Dynamic Pitch Variation**: Intelligent pitch adjustments based on content
- **Natural Pausing**: Linguistically-aware break placement and timing
- **Rate Control**: Speaking rate adapted to content complexity
- **Prosodic Segmentation**: Segments respect syntactic and semantic boundaries

## Development

### Project Structure

```
lib/prosodic-text-converter/
├── audio/              # Audio processing and pitch analysis
├── analysis/           # Spectrogram and prosodic pattern analysis
├── text/               # Linguistic text preprocessing
├── conversion/         # LLM integration and SSML formatting
└── core/               # CLI interface and main converter
```

### Testing

```bash
# Run tests
bundle exec rspec

# Run linting
bundle exec rubocop

# Auto-fix style issues
bundle exec rubocop -a
```

### Adding New Backends

1. Implement the pitch analyzer interface in `lib/prosodic-text-converter/audio/`
2. Register the backend in `PitchAnalyzerFactory`
3. Add system dependencies to `setup.sh` and `Dockerfile`
4. Update documentation

## Configuration

### Environment Variables

Configure your API keys in the `.env` file (copy from `.env.example`):

```bash
# LLM API Keys (at least one required)
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
GEMINI_API_KEY=...
ELEVENLABS_API_KEY=...

# Optional: Default backend selection
PROSODIC_PITCH_BACKEND=aubio  # or "sonic_annotator"
```

### Audio Format Support

Supports any audio format that SoX can read:

- WAV, MP3, FLAC, OGG, M4A, AAC
- Automatically handles format conversion and resampling

## Troubleshooting

### Common Issues

**No backends available**

```bash
# Install aubio
sudo apt-get install aubio-tools  # Ubuntu/Debian
brew install aubio                 # macOS

# Or run setup script
./setup.sh
```

**LLM API errors**

```bash
# Verify API key is set
echo $GEMINI_API_KEY

# Test with simple input
echo "test" | ./bin/prosodic-text-converter --provider=gemini
```

**Audio file not found**

```bash
# Verify file exists and is readable
ls -la your-audio-file.wav
file your-audio-file.wav
```

### Debug Mode

Run with verbose logging to diagnose issues:

```bash
./bin/prosodic-text-converter --verbose --audio=test.wav input.txt
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Run the test suite and linting
5. Submit a pull request

## License

[License information to be added]

## Acknowledgments

- [Aubio](https://aubio.org/) - Real-time audio analysis
- [Sonic Annotator](https://code.soundsoftware.ac.uk/projects/sonic-annotator) - Research-grade audio analysis
- [lingua](https://github.com/dbalatero/lingua) - Natural language processing
- [RubyLLM](https://github.com/mariochavez/ruby_llm) - Multi-provider LLM interface
