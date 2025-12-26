# Interactive TUI Interface

The Prosodic Text Converter now includes a Terminal User Interface (TUI) that provides an interactive way to configure and run the application.

## Usage

```bash
./bin/prosodic-tui
```

## Features

The TUI provides interactive prompts for:

### 1. Environment Setup
- **API Key Configuration**: Set up API keys for various LLM providers:
  - OpenAI (GPT models)
  - Anthropic (Claude models) 
  - Google Gemini
  - ElevenLabs (speech synthesis)
- **System Configuration**: Configure pitch backend, logging levels, etc.
- **Automatic .env Creation**: Creates or updates `.env` file with your settings

### 2. Input Options
- **Text File**: Select an existing text file to process
- **Direct Input**: Type or paste text directly into the interface
- **Clipboard Input**: Load text from system clipboard (requires `clipboard` gem)

### 3. Processing Configuration
- **Audio Analysis**: Option to extract prosodic patterns from audio files
  - Supports various audio formats (WAV, MP3, FLAC, etc.)
  - Choose between Aubio (fast) or Sonic Annotator (research-grade) backends
- **Predefined Patterns**: Select from built-in prosodic patterns:
  - **Deliberate**: 1.0s segments, 350ms pauses (default)
  - **Rapid**: 0.6s segments, 200ms pauses  
  - **Contemplative**: 1.4s segments, 500ms pauses

### 4. LLM Provider Selection
- **Provider Choice**: Select from available LLM providers based on configured API keys
- **Model Selection**: Choose specific models for your selected provider
- **Timeout Configuration**: Set custom timeouts for LLM and analysis operations

### 5. Output Configuration
- **Output Directory**: Choose or create output directory for generated files
- **Format Selection**: Choose output format (SSML, XML, plain text)
- **Speech Synthesis**: Optional ElevenLabs voice synthesis with voice selection

### 6. Advanced Options
- **Verbose Output**: Enable detailed logging and analysis information
- **Custom Timeouts**: Configure LLM and audio analysis timeouts
- **Spectrogram Directory**: Set custom directory for generated spectrograms

## Workflow

1. **Environment Check**: TUI checks for existing `.env` file and offers to create/update it
2. **Configuration**: Interactive prompts collect all necessary options
3. **Output Setup**: Choose and create output directory
4. **Confirmation**: Review all settings before execution
5. **Processing**: Execute conversion with real-time progress feedback
6. **Results**: Save outputs and optionally generate speech synthesis

## Dependencies

The TUI requires the `tty-prompt` gem. Install it with:

```bash
bundle install
```

Or manually:

```bash
gem install tty-prompt
```

## File Structure

- `lib/prosodic-text-converter/core/tui.rb` - Main TUI implementation
- `bin/prosodic-tui` - Executable script
- `.env` - Generated environment configuration file
- `./output/` - Default output directory (configurable)

## Error Handling

The TUI includes comprehensive error handling for:
- Missing dependencies
- Invalid file paths
- API key validation
- Directory creation failures
- Conversion errors

All errors are displayed with user-friendly messages and options to retry or reconfigure.