# frozen_string_literal: true

# Attempts to load the .env file, overwriting existing environment variables.
# If an error occurs, it displays an error message.
begin
  Dotenv.load(".env", overwrite: true)
rescue StandardError => e
  puts "Error loading .env file: #{e.message}"
end

require_relative 'prosodic-text-converter/version'

# Core logging (must be loaded early)
require_relative 'prosodic-text-converter/core/logging'

# Audio processing
require_relative 'prosodic-text-converter/audio/spectrogram'
require_relative 'prosodic-text-converter/audio/pitch_analyzer'

# Analysis
require_relative 'prosodic-text-converter/analysis/spectrogram_analyzer'
require_relative 'prosodic-text-converter/analysis/prosodic_pattern'

# Text processing
require_relative 'prosodic-text-converter/text/text_analyzer'

# Conversion
require_relative 'prosodic-text-converter/conversion/llm_converter'
require_relative 'prosodic-text-converter/conversion/ssml_formatter'

# Core functionality
require_relative 'prosodic-text-converter/core/config'
require_relative 'prosodic-text-converter/core/converter'
require_relative 'prosodic-text-converter/core/cli'
