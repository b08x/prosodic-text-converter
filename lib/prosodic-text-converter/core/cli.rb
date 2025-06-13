# frozen_string_literal: true

require 'timeout'
require_relative 'logging'
require_relative 'converter'
require_relative 'config'
require_relative '../audio/speech_synthesizer'

module ProsodicTextConverter
  # CLI interface for prosodic text conversion
  #
  # @example Basic usage
  #   CLI.run(['--pattern=deliberate', 'input.txt'])
  #
  # @example Audio analysis
  #   CLI.run(['--audio=voice.wav', '--pitch-backend=aubio', 'input.txt'])
  class CLI
    extend Logging

    # Main entry point for CLI execution
    #
    # @param args [Array<String>] command line arguments
    # @return [void]
    def self.run(args = ARGV)
      # Initialize configuration from all sources
      config = Config.from_cli_args(args)

      logger.info("Starting prosodic text converter with args: #{args.join(' ')}")

      if args.empty? || config.get(:help)
        print_usage
        return
      end

      if config.list_backends?
        list_available_backends
        return
      end

      if config.health_check?
        perform_health_check
        return
      end

      if config.list_voices?
        list_elevenlabs_voices
        return
      end

      logger.debug("Configuration loaded: #{config.to_hash}")

      # Validate dependencies with timeout
      validate_dependencies(config.get(:pitch_backend).to_sym)

      # Initialize converter with error handling
      converter = create_converter(config)
      logger.info("Converter initialized with backend: #{config.get(:pitch_backend)}")

      # Execute conversion based on mode
      result = execute_conversion(converter, config)

      # Handle ElevenLabs synthesis if voice specified
      synthesize_with_elevenlabs(result[:ssml_output], config) if config.get(:elevenlabs_voice) && result[:ssml_output]

      # Output results
      output_results(result, config.verbose?)
    rescue Interrupt
      logger.warn('Operation interrupted by user')
      exit 130
    rescue Timeout::Error => e
      logger.error("Operation timed out: #{e.message}")
      warn 'Error: Operation timed out. Try with smaller audio files or simpler operations.'
      exit 124
    rescue ArgumentError => e
      logger.error("Invalid arguments: #{e.message}")
      warn "Error: #{e.message}"
      print_usage
      exit 1
    rescue StandardError => e
      logger.error("Unexpected error: #{e.class.name} - #{e.message}")
      logger.debug("Backtrace: #{e.backtrace.join("\n")}")
      warn "Error: #{e.message}"
      exit 1
    end

    # Validate configuration and files
    #
    # @param config [Config] configuration object
    # @return [void]
    # @raise [ArgumentError] if configuration is invalid
    def self.validate_configuration(config)
      # Validate audio file if provided
      audio_file = config.get(:audio_file)
      raise ArgumentError, "Audio file not found: #{audio_file}" if audio_file && !File.exist?(audio_file)

      # Validate input file if provided
      input_file = config.input_file
      return unless input_file && !File.exist?(input_file) && !config.analyze_only?

      raise ArgumentError, "Input file not found: #{input_file}"
    end

    # Validate dependencies and pitch backend availability
    #
    # @param pitch_backend [Symbol] the pitch backend to validate
    # @return [void]
    # @raise [RuntimeError] if dependencies are not available
    def self.validate_dependencies(pitch_backend)
      available_backends = begin
        Timeout.timeout(5) do
          Converter.available_pitch_backends
        end
      rescue Timeout::Error
        logger.error('Timeout checking available backends')
        raise 'Timeout while checking dependencies'
      end

      if available_backends.empty?
        error_msg = 'No pitch analysis backends available'
        logger.error(error_msg)
        raise "#{error_msg}. Install aubio: apt-get install aubio-tools (Linux) or brew install aubio (macOS)"
      elsif !available_backends.include?(pitch_backend)
        error_msg = "Pitch backend '#{pitch_backend}' not available"
        logger.error("#{error_msg}. Available: #{available_backends}")
        raise "#{error_msg}. Available backends: #{available_backends.join(', ')}"
      end

      logger.info("Dependencies validated. Available backends: #{available_backends}")
    end

    # Create converter instance with error handling
    #
    # @param config [Config] configuration object
    # @return [Converter] configured converter instance
    def self.create_converter(config)
      validate_configuration(config)

      Timeout.timeout(config.get(:llm_timeout, 30)) do
        Converter.new(
          pattern: config.predefined_pattern,
          provider: config.get(:provider).to_sym,
          model: config.get(:model),
          pitch_backend: config.get(:pitch_backend).to_sym,
          output_dir: config.get(:output_dir)
        )
      end
    rescue Timeout::Error
      logger.error('Timeout creating converter')
      raise 'Timeout while initializing converter'
    rescue StandardError => e
      logger.error("Failed to create converter: #{e.message}")
      raise "Failed to initialize converter: #{e.message}"
    end

    # Execute the conversion based on configuration
    #
    # @param converter [Converter] the converter instance
    # @param config [Config] configuration object
    # @return [Hash] conversion results
    def self.execute_conversion(converter, config)
      audio_file = config.get(:audio_file)
      analysis_timeout = config.get(:analysis_timeout, 60)

      if audio_file
        if config.analyze_only?
          logger.info('Performing audio analysis only')
          Timeout.timeout(analysis_timeout) do
            converter.extract_pattern_from_audio(audio_file, output_dir: config.get(:spectrogram_dir))
          end
        else
          raise ArgumentError, 'Text file required when using --audio option' unless config.input_file

          text = read_input_text(config)
          logger.info('Converting text with audio analysis')
          Timeout.timeout(analysis_timeout * 2) do
            converter.convert_with_audio_analysis(text.strip, audio_file)
          end
        end
      else
        text = read_input_text(config)
        logger.info('Converting text without audio analysis')
        Timeout.timeout(config.get(:llm_timeout, 60)) do
          converter.convert(text.strip)
        end
      end
    end

    # Read input text from file or stdin
    #
    # @param config [Config] configuration object
    # @return [String] input text
    def self.read_input_text(config)
      input_file = config.input_file
      audio_file = config.get(:audio_file)

      if input_file && File.exist?(input_file)
        logger.debug("Reading text from file: #{input_file}")
        File.read(input_file)
      elsif !audio_file || !input_file
        logger.debug('Reading text from stdin')
        $stdin.read
      else
        logger.debug("Reading text from file: #{input_file}")
        File.read(input_file)
      end
    rescue StandardError => e
      logger.error("Failed to read input text: #{e.message}")
      raise "Failed to read input text: #{e.message}"
    end

    # Output conversion results
    #
    # @param result [Hash] conversion results
    # @param verbose [Boolean] whether to show verbose output
    # @return [void]
    def self.output_results(result, verbose)
      if result[:ssml_output]
        puts result[:ssml_output]
      elsif result[:spectrogram_file]
        puts 'Audio analysis complete:'
        puts "Spectrogram: #{result[:spectrogram_file]}"
        puts "Pitch backend: #{result[:pitch_backend_used]}"
        puts "Extracted pattern: #{result[:extracted_pattern]}"

        if result[:analysis][:prosodic_features][:analysis_method]
          puts "Analysis method: #{result[:analysis][:prosodic_features][:analysis_method]}"
        end
      end

      output_verbose_info(result) if verbose

      logger.info('Conversion completed successfully')
    end

    # Output verbose analysis information
    #
    # @param result [Hash] conversion results
    # @return [void]
    def self.output_verbose_info(result)
      warn "\n--- Analysis ---"
      warn "Pattern: #{result[:pattern_used]}" if result[:pattern_used]
      warn "Sentences: #{result[:sentences_processed]}" if result[:sentences_processed]
      warn "Timing: #{result[:timing_analysis]}" if result[:timing_analysis]

      return unless result[:audio_analysis]

      warn "\n--- Audio Analysis ---"
      warn "Spectrogram: #{result[:audio_analysis][:spectrogram_file]}"
      warn "Pitch backend: #{result[:audio_analysis][:pitch_backend_used]}"
      warn "Prosodic features: #{result[:audio_analysis][:analysis][:prosodic_features]}"

      return unless result[:audio_analysis][:analysis][:pitch_analysis]

      pitch_data = result[:audio_analysis][:analysis][:pitch_analysis]
      warn "Pitch data points: #{pitch_data&.length || 0}"
    end

    # Perform health check of dependencies
    #
    # @return [void]
    def self.perform_health_check
      puts 'Prosodic Text Converter - Health Check'
      puts '=' * 40

      begin
        # Check Ruby version
        puts "✓ Ruby #{RUBY_VERSION}"

        # Check required gems
        check_gem('ruby_llm')
        check_gem('nokogiri')
        check_gem('mini_magick')

        # Check system dependencies
        check_system_dependency('sox', 'SoX audio processing')
        check_system_dependency('convert', 'ImageMagick')
        check_system_dependency('aubio', 'Aubio pitch analysis', optional: true)
        check_system_dependency('sonic-annotator', 'Sonic Annotator', optional: true)

        # Check pitch backends
        backends = Converter.available_pitch_backends
        if backends.empty?
          puts '⚠ No pitch analysis backends available'
        else
          backends.each do |backend|
            puts "✓ Pitch backend: #{backend}"
          end
        end

        puts "\nHealth check completed successfully!"
      rescue StandardError => e
        logger.error("Health check failed: #{e.message}")
        puts "✗ Health check failed: #{e.message}"
        exit 1
      end
    end

    # Check if a gem is available
    #
    # @param gem_name [String] name of the gem
    # @return [void]
    def self.check_gem(gem_name)
      require gem_name
      puts "✓ Gem: #{gem_name}"
    rescue LoadError
      puts "✗ Missing gem: #{gem_name}"
      raise "Required gem not found: #{gem_name}"
    end

    # Check if a system dependency is available
    #
    # @param command [String] command to check
    # @param description [String] description of the dependency
    # @param optional [Boolean] whether the dependency is optional
    # @return [void]
    def self.check_system_dependency(command, description, optional: false)
      if system("which #{command} > /dev/null 2>&1")
        puts "✓ #{description}"
      elsif optional
        puts "⚠ Optional: #{description} (not found)"
      else
        puts "✗ Required: #{description} (not found)"
        raise "Required system dependency not found: #{command}"
      end
    end

    # List available pitch analysis backends with detailed information
    #
    # @return [void]
    def self.list_available_backends
      backends = Converter.available_pitch_backends

      puts 'Available pitch analysis backends:'
      if backends.empty?
        puts '  None found. Install aubio or sonic-annotator.'
      else
        backends.each do |backend|
          status = case backend
                   when :aubio
                     '✓ Aubio - Fast, accurate, excellent for speech (recommended for most use cases)'
                   when :sonic_annotator
                     '✓ Sonic Annotator - Research-grade analysis with comprehensive prosodic metrics'
                   else
                     "✓ #{backend}"
                   end
          puts "  #{status}"
        end
      end

      puts "\nBackend Features:"
      puts '  Aubio:'
      puts '    • YIN pitch tracking algorithm'
      puts '    • Fast processing, low memory usage'
      puts '    • Excellent for production pipelines'
      puts '    • Speech-optimized frequency analysis'
      puts ''
      puts '  Sonic Annotator:'
      puts '    • pYIN probabilistic pitch tracking'
      puts '    • Advanced tempo and rhythm analysis'
      puts '    • Multiple simultaneous feature extraction'
      puts '    • Research-grade accuracy with confidence measures'
      puts '    • Extensible plugin ecosystem'
      puts ''
      puts 'Installation:'
      puts '  Aubio: apt-get install aubio-tools (Linux) or brew install aubio (macOS)'
      puts '  Sonic Annotator: https://vamp-plugins.org/sonic-annotator/'
      puts '    • Also install Vamp plugins: pyin, vamp-example-plugins'
      puts '    • macOS: brew install sonic-visualiser (includes sonic-annotator)'
    end

    # List available ElevenLabs voices
    #
    # @return [void]
    def self.list_elevenlabs_voices
      synthesizer = SpeechSynthesizer.new(provider: :elevenlabs)
      voices = synthesizer.get_voices

      puts 'Available ElevenLabs voices:'
      if voices.empty?
        puts '  No voices found. Check your ELEVENLABS_API_KEY.'
      else
        voices.each do |voice|
          puts "  #{voice['voice_id']} - #{voice['name']}"
          puts "    Category: #{voice['category']}" if voice['category']
          puts "    Description: #{voice['description']}" if voice['description']
          puts ''
        end
      end
    rescue StandardError => e
      logger.error("Failed to list ElevenLabs voices: #{e.message}")
      puts "Error: #{e.message}"
      puts 'Make sure ELEVENLABS_API_KEY environment variable is set.'
      exit 1
    end

    # Synthesize speech using ElevenLabs
    #
    # @param ssml_text [String] SSML text to synthesize
    # @param config [Config] configuration object
    # @return [void]
    def self.synthesize_with_elevenlabs(ssml_text, config)
      voice = config.get(:elevenlabs_voice)
      logger.info("Synthesizing speech with ElevenLabs voice: #{voice}")

      synthesizer = SpeechSynthesizer.new(provider: :elevenlabs)

      synthesis_options = {}
      elevenlabs_model = config.get(:elevenlabs_model)
      synthesis_options[:model_id] = elevenlabs_model if elevenlabs_model

      audio_data = synthesizer.synthesize_ssml(
        ssml_text,
        voice: voice,
        **synthesis_options
      )

      output_file = config.get(:output_file) || 'output.mp3'
      synthesizer.save_audio(audio_data, output_file)

      logger.info("Speech synthesis completed: #{output_file}")
    rescue StandardError => e
      logger.error("ElevenLabs synthesis failed: #{e.message}")
      puts "Error synthesizing speech: #{e.message}"
      exit 1
    end

    # Print usage information and command-line help
    #
    # @return [void]
    def self.print_usage
      puts <<~USAGE
        Prosodic Text Converter

        Usage: #{$0} [options] [input_file]

        Options:
          --pattern=NAME          Use predefined pattern (deliberate, rapid, contemplative)
          --audio=FILE           Extract prosodic pattern from audio file
          --pitch-backend=NAME   Pitch analysis backend (aubio, sonic_annotator)
          --analyze-only         Only analyze audio file, don't convert text
          --spectrogram-dir=DIR  Output directory for spectrograms (default: ./spectrograms)
          --provider=NAME        LLM provider (openai, anthropic, ollama, etc.)
          --model=NAME           Model name (gpt-4, claude-3-sonnet, etc.)
          --elevenlabs-voice=ID  ElevenLabs voice ID for speech synthesis
          --elevenlabs-model=ID  ElevenLabs model (eleven_monolingual_v1, etc.)
          --output=FILE          Output audio file (when using ElevenLabs)
          --verbose              Show analysis information
          --list-backends        Show available pitch analysis backends
          --list-voices          Show available ElevenLabs voices
          --help                Show this help
        #{'  '}
        Patterns:
          deliberate             1.0s segments, 350ms pauses (default)
          rapid                  0.6s segments, 200ms pauses#{'  '}
          contemplative          1.4s segments, 500ms pauses
        #{'  '}
        Providers (via RubyLLM):
          openai                OpenAI GPT models (requires OPENAI_API_KEY)
          anthropic             Anthropic Claude models (requires ANTHROPIC_API_KEY)
          ollama                Local Ollama models
        #{'  '}
        Pitch Backends:
          aubio                 Fast, accurate, recommended for production use
          sonic_annotator       Research-grade with comprehensive prosodic analysis
        #{'  '}
        Audio Analysis:
          Requires SoX and a pitch analysis backend (aubio or sonic-annotator)
          Supported formats: WAV, MP3, FLAC, etc. (anything SoX can read)
        #{'  '}
        Backend Selection Guide:
          • Use aubio for: Production pipelines, fast processing, speech applications
          • Use sonic_annotator for: Research, detailed prosodic analysis, academic work
        #{'  '}
        Examples:
          # List available pitch backends and their features
          #{$0} --list-backends
        #{'  '}
          # Basic text conversion
          echo "Hello world" | #{$0}
        #{'  '}
          # Use predefined pattern
          #{$0} --pattern=rapid --provider=anthropic input.txt
        #{'  '}
          # Fast analysis with aubio (recommended for most use cases)
          #{$0} --audio=voice_sample.wav --pitch-backend=aubio input.txt
        #{'  '}
          # Comprehensive research-grade analysis with sonic-annotator
          #{$0} --audio=speaker.wav --pitch-backend=sonic_annotator input.txt
        #{'  '}
          # Analyze audio only with detailed metrics
          #{$0} --audio=voice_sample.wav --pitch-backend=sonic_annotator --analyze-only --verbose
        #{'  '}
          # Compare backends on same audio
          #{$0} --audio=test.wav --pitch-backend=aubio --analyze-only > aubio_analysis.txt
          #{$0} --audio=test.wav --pitch-backend=sonic_annotator --analyze-only > sonic_analysis.txt
        #{'  '}
          # Full pipeline with research-grade analysis
          #{$0} --audio=speaker.wav --pitch-backend=sonic_annotator --provider=anthropic --model=claude-3-sonnet text.txt
        #{'  '}
          # Generate speech with ElevenLabs
          #{$0} --elevenlabs-voice=21m00Tcm4TlvDq8ikWAM --output=speech.mp3 input.txt
        #{'  '}
          # List available ElevenLabs voices
          #{$0} --list-voices
        #{'  '}
          # Complete pipeline: analyze audio, convert text, and synthesize speech
          #{$0} --audio=sample.wav --elevenlabs-voice=21m00Tcm4TlvDq8ikWAM --output=result.mp3 text.txt
      USAGE
    end
  end
end
