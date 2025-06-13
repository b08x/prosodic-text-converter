# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a Ruby-based prosodic text converter that analyzes audio files to extract prosodic patterns and converts text to SSML (Speech Synthesis Markup Language) with natural speech timing. The application integrates sophisticated pitch analysis backends with AI-powered language models to produce intelligent prosodic markup.

## Common Development Commands

### Testing and Quality Assurance

```bash
# Run RSpec tests
bundle exec rspec

# Run tests with coverage
bundle exec rake coverage

# Run RuboCop linter
bundle exec rubocop

# Auto-fix RuboCop issues
bundle exec rubocop -a

# Run comprehensive quality checks
bundle exec rake quality

# Run all checks (tests + linting + documentation coverage)
bundle exec rake check
```

### Documentation

```bash
# Generate RDoc documentation
bundle exec rake rdoc

# Generate YARD documentation (enhanced)
bundle exec rake yard

# Generate both documentation formats
bundle exec rake docs

# Serve YARD documentation locally
bundle exec rake yard:serve

# Check documentation coverage
bundle exec rake doc_coverage
```

### Application Usage

```bash
# Run the main CLI application
./bin/prosodic-text-converter --help

# Run the interactive TUI
./bin/prosodic-tui

# Example conversions
echo "Hello world" | ./bin/prosodic-text-converter --pattern=deliberate --provider=gemini
./bin/prosodic-text-converter --audio=voice.wav --pitch-backend=aubio input.txt
```

### Docker Operations

```bash
# Build container
docker build -t prosodic-text-converter .

# Run with help
docker run --rm prosodic-text-converter --help

# Health check
docker run --rm prosodic-text-converter --health-check

# List available backends
docker run --rm prosodic-text-converter --list-backends
```

## Architecture Overview

### Core Processing Pipeline

1. **Audio Analysis** (optional): Extract prosodic patterns from reference audio using Aubio or Sonic Annotator
2. **Text Preprocessing**: Sentence segmentation, tokenization, and linguistic analysis using lingua and pragmatic_tokenizer
3. **LLM Processing**: Generate prosodic markup based on linguistic context and audio patterns using multiple AI providers
4. **SSML Generation**: Validate and format final Speech Synthesis Markup Language output

### Key Components

- **CLI Interface** (`lib/prosodic-text-converter/core/cli.rb`): Command-line interface with comprehensive option parsing
- **TUI Interface** (`lib/prosodic-text-converter/core/tui.rb`): Interactive terminal user interface for guided configuration
- **Converter Engine** (`lib/prosodic-text-converter/core/converter.rb`): Main orchestrator for audio analysis and text processing
- **Pitch Analysis Factory** (`lib/prosodic-text-converter/audio/pitch_analyzer.rb`): Factory pattern supporting multiple backends (Aubio, Sonic Annotator)
- **LLM Converter** (`lib/prosodic-text-converter/conversion/llm_converter.rb`): AI-powered prosodic decision making with multi-provider support
- **Text Analyzer** (`lib/prosodic-text-converter/text/text_analyzer.rb`): Linguistic preprocessing and analysis
- **SSML Formatter** (`lib/prosodic-text-converter/conversion/ssml_formatter.rb`): Output validation and formatting

### Audio Backend Architecture

The application uses a factory pattern for pitch analysis backends:

- **Aubio Backend**: Fast YIN pitch detection, ideal for production use (~0.4s processing time)
- **Sonic Annotator Backend**: Research-grade pYIN analysis with higher precision (~2-3s processing time)

Both backends implement a common interface and are selected via the `--pitch-backend` option or `PROSODIC_PITCH_BACKEND` environment variable.

### LLM Integration Pattern

Multi-provider LLM support through the `ruby_llm` gem:
- **OpenAI**: GPT models via direct API calls
- **Anthropic**: Claude models with streaming support
- **Google Gemini**: Gemini models through official SDK
- **Ollama**: Local model support

Provider selection is handled via the `--provider` flag with automatic fallback mechanisms and comprehensive error handling.

## Configuration Management

### Environment Variables

API keys and configuration are managed through `.env` files:

```bash
# Required: At least one LLM provider API key
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
GEMINI_API_KEY=...
ELEVENLABS_API_KEY=...

# Optional: Default backend selection
PROSODIC_PITCH_BACKEND=aubio
```

### Configuration Sources

The application loads configuration from multiple sources in priority order:
1. Command-line arguments (highest priority)
2. Environment variables
3. Configuration files (`config/defaults.yml`)
4. Built-in defaults (lowest priority)

## Testing Architecture

### Test Structure

```
spec/
├── analysis/           # Spectrogram and pattern analysis tests
├── audio/             # Pitch analyzer and audio processing tests
├── conversion/        # LLM converter and SSML formatter tests
├── core/              # Main converter and CLI tests
└── support/           # Test helpers and fixtures
```

### Key Testing Patterns

- **Mock Audio Processing**: Tests use sample audio files (`spec/test_files/`) to avoid external dependencies
- **LLM API Mocking**: External API calls are mocked to ensure consistent test execution
- **Backend Validation**: Tests verify both Aubio and Sonic Annotator backends when available
- **Error Handling**: Comprehensive error condition testing for missing dependencies and invalid inputs

## Development Dependencies

### System Requirements

- Ruby 3.1+
- SoX (audio processing)
- ImageMagick (spectrogram generation)
- Aubio tools (recommended) or Sonic Annotator (optional)

### Ruby Gem Dependencies

Key gems used in the application:
- `ruby_llm`: Multi-provider LLM interface
- `pragmatic_tokenizer` + `lingua`: Text analysis and linguistic processing
- `aubio`: Ruby bindings for Aubio audio analysis
- `rdf` + `rdf-turtle`: RDF parsing for Sonic Annotator output
- `tty-prompt` + `tty-config`: Interactive TUI components
- `mini_magick`: Image processing for spectrograms
- `nokogiri`: XML/HTML parsing for SSML validation

## TUI Interface

The interactive Terminal User Interface (`./bin/prosodic-tui`) provides guided configuration for:
- API key setup and validation
- Input method selection (file, direct input, clipboard)
- Audio analysis configuration
- LLM provider and model selection
- Output format and directory configuration
- Real-time processing feedback

## Output Formats

The application generates SSML with intelligent prosodic markup:
- **Dynamic Pitch Variation**: Context-aware pitch adjustments
- **Natural Pausing**: Linguistically-informed break placement
- **Rate Control**: Speaking rate adaptation based on content complexity
- **Prosodic Segmentation**: Segments that respect syntactic and semantic boundaries

Results can be saved as JSON and CSV files in the specified output directory with the `--output-dir` option.