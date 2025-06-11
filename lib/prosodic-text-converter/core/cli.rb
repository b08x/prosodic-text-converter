# frozen_string_literal: true

require 'logger'
require 'timeout'
require_relative 'converter'

module ProsodicTextConverter
  # CLI interface for prosodic text conversion
  # 
  # @example Basic usage
  #   CLI.run(['--pattern=deliberate', 'input.txt'])
  #
  # @example Audio analysis
  #   CLI.run(['--audio=voice.wav', '--pitch-backend=aubio', 'input.txt'])
  class CLI
    # @return [Logger] the logger instance
    attr_reader :logger

    # Initialize the CLI with optional logger
    #
    # @param logger [Logger] custom logger instance
    def self.setup_logger(logger = nil)
      @logger = logger || Logger.new($stderr).tap do |log|
        log.level = Logger::INFO
        log.formatter = proc do |severity, datetime, progname, msg|
          "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
        end
      end
    end

    # Get the current logger instance
    #
    # @return [Logger] the logger
    def self.logger
      @logger ||= setup_logger
    end
    # Main entry point for CLI execution
    #
    # @param args [Array<String>] command line arguments
    # @return [void]
    def self.run(args = ARGV)
      begin
        logger.info("Starting prosodic text converter with args: #{args.join(' ')}")
        
        if args.empty? || args.include?('--help')
          print_usage
          return
        end

        if args.include?('--list-backends')
          list_available_backends
          return
        end

        if args.include?('--health-check')
          perform_health_check
          return
        end

        # Parse arguments with validation
        options = parse_arguments(args)
        logger.debug("Parsed options: #{options}")
        
        # Validate dependencies with timeout
        validate_dependencies(options[:pitch_backend])
        
        # Initialize converter with error handling
        converter = create_converter(options)
        logger.info("Converter initialized with backend: #{options[:pitch_backend]}")
        
        # Execute conversion based on mode
        result = execute_conversion(converter, options, args)
        
        # Output results
        output_results(result, args.include?('--verbose'))
        
      rescue Interrupt
        logger.warn("Operation interrupted by user")
        exit 130
      rescue Timeout::Error => e
        logger.error("Operation timed out: #{e.message}")
        $stderr.puts "Error: Operation timed out. Try with smaller audio files or simpler operations."
        exit 124
      rescue ArgumentError => e
        logger.error("Invalid arguments: #{e.message}")
        $stderr.puts "Error: #{e.message}"
        print_usage
        exit 1
      rescue StandardError => e
        logger.error("Unexpected error: #{e.class.name} - #{e.message}")
        logger.debug("Backtrace: #{e.backtrace.join("\n")}")
        $stderr.puts "Error: #{e.message}"
        exit 1
      end
    end

    private

    # Parse command line arguments
    #
    # @param args [Array<String>] command line arguments
    # @return [Hash] parsed options
    def self.parse_arguments(args)
      pattern_name = args.find { |arg| arg.start_with?('--pattern=') }&.split('=', 2)&.last&.to_sym
      provider_arg = args.find { |arg| arg.start_with?('--provider=') }&.split('=', 2)&.last&.to_sym
      model_arg = args.find { |arg| arg.start_with?('--model=') }&.split('=', 2)&.last
      pitch_backend_arg = args.find { |arg| arg.start_with?('--pitch-backend=') }&.split('=', 2)&.last&.to_sym
      audio_file = args.find { |arg| arg.start_with?('--audio=') }&.split('=', 2)&.last
      spectrogram_dir = args.find { |arg| arg.start_with?('--spectrogram-dir=') }&.split('=', 2)&.last || './spectrograms'
      
      # Get non-option arguments
      input_files = args.reject { |arg| arg.start_with?('--') }
      input_file = input_files.first
      
      pattern = Converter.predefined_patterns[pattern_name] if pattern_name
      provider = provider_arg || :gemini
      model = model_arg || 'gemini-2.0-flash'
      pitch_backend = pitch_backend_arg || :aubio

      # Validate audio file if provided
      if audio_file && !File.exist?(audio_file)
        raise ArgumentError, "Audio file not found: #{audio_file}"
      end

      # Validate input file if provided
      if input_file && !File.exist?(input_file) && !args.include?('--analyze-only')
        raise ArgumentError, "Input file not found: #{input_file}"
      end
      
      {
        pattern: pattern,
        provider: provider,
        model: model,
        pitch_backend: pitch_backend,
        audio_file: audio_file,
        spectrogram_dir: spectrogram_dir,
        input_file: input_file
      }
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
        logger.error("Timeout checking available backends")
        raise RuntimeError, "Timeout while checking dependencies"
      end
      
      if available_backends.empty?
        error_msg = "No pitch analysis backends available"
        logger.error(error_msg)
        raise RuntimeError, "#{error_msg}. Install aubio: apt-get install aubio-tools (Linux) or brew install aubio (macOS)"
      elsif !available_backends.include?(pitch_backend)
        error_msg = "Pitch backend '#{pitch_backend}' not available"
        logger.error("#{error_msg}. Available: #{available_backends}")
        raise RuntimeError, "#{error_msg}. Available backends: #{available_backends.join(', ')}"
      end
      
      logger.info("Dependencies validated. Available backends: #{available_backends}")
    end

    # Create converter instance with error handling
    #
    # @param options [Hash] parsed options
    # @return [Converter] configured converter instance
    def self.create_converter(options)
      Timeout.timeout(10) do
        Converter.new(
          pattern: options[:pattern],
          provider: options[:provider],
          model: options[:model],
          pitch_backend: options[:pitch_backend]
        )
      end
    rescue Timeout::Error
      logger.error("Timeout creating converter")
      raise RuntimeError, "Timeout while initializing converter"
    rescue StandardError => e
      logger.error("Failed to create converter: #{e.message}")
      raise RuntimeError, "Failed to initialize converter: #{e.message}"
    end

    # Execute the conversion based on options
    #
    # @param converter [Converter] the converter instance
    # @param options [Hash] parsed options
    # @param args [Array<String>] original arguments
    # @return [Hash] conversion results
    def self.execute_conversion(converter, options, args)
      if options[:audio_file]
        if args.include?('--analyze-only')
          logger.info("Performing audio analysis only")
          Timeout.timeout(60) do
            converter.extract_pattern_from_audio(options[:audio_file], output_dir: options[:spectrogram_dir])
          end
        else
          unless options[:input_file]
            raise ArgumentError, "Text file required when using --audio option"
          end
          
          text = read_input_text(options)
          logger.info("Converting text with audio analysis")
          Timeout.timeout(120) do
            converter.convert_with_audio_analysis(text.strip, options[:audio_file])
          end
        end
      else
        text = read_input_text(options)
        logger.info("Converting text without audio analysis")
        Timeout.timeout(60) do
          converter.convert(text.strip)
        end
      end
    end

    # Read input text from file or stdin
    #
    # @param options [Hash] parsed options
    # @return [String] input text
    def self.read_input_text(options)
      if options[:input_file] && File.exist?(options[:input_file])
        logger.debug("Reading text from file: #{options[:input_file]}")
        File.read(options[:input_file])
      elsif !options[:audio_file] || !options[:input_file]
        logger.debug("Reading text from stdin")
        $stdin.read
      else
        logger.debug("Reading text from file: #{options[:input_file]}")
        File.read(options[:input_file])
      end
    rescue StandardError => e
      logger.error("Failed to read input text: #{e.message}")
      raise RuntimeError, "Failed to read input text: #{e.message}"
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
        puts "Audio analysis complete:"
        puts "Spectrogram: #{result[:spectrogram_file]}"
        puts "Pitch backend: #{result[:pitch_backend_used]}"
        puts "Extracted pattern: #{result[:extracted_pattern]}"
        
        if result[:analysis][:prosodic_features][:analysis_method]
          puts "Analysis method: #{result[:analysis][:prosodic_features][:analysis_method]}"
        end
      end
      
      if verbose
        output_verbose_info(result)
      end
      
      logger.info("Conversion completed successfully")
    end

    # Output verbose analysis information
    #
    # @param result [Hash] conversion results
    # @return [void]
    def self.output_verbose_info(result)
      $stderr.puts "\n--- Analysis ---"
      $stderr.puts "Pattern: #{result[:pattern_used]}" if result[:pattern_used]
      $stderr.puts "Sentences: #{result[:sentences_processed]}" if result[:sentences_processed]
      $stderr.puts "Timing: #{result[:timing_analysis]}" if result[:timing_analysis]
      
      if result[:audio_analysis]
        $stderr.puts "\n--- Audio Analysis ---"
        $stderr.puts "Spectrogram: #{result[:audio_analysis][:spectrogram_file]}"
        $stderr.puts "Pitch backend: #{result[:audio_analysis][:pitch_backend_used]}"
        $stderr.puts "Prosodic features: #{result[:audio_analysis][:analysis][:prosodic_features]}"
        
        if result[:audio_analysis][:analysis][:pitch_analysis]
          pitch_data = result[:audio_analysis][:analysis][:pitch_analysis]
          $stderr.puts "Pitch data points: #{pitch_data&.length || 0}"
        end
      end
    end

    # Perform health check of dependencies
    #
    # @return [void]
    def self.perform_health_check
      puts "Prosodic Text Converter - Health Check"
      puts "=" * 40
      
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
          puts "⚠ No pitch analysis backends available"
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
      raise RuntimeError, "Required gem not found: #{gem_name}"
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
        raise RuntimeError, "Required system dependency not found: #{command}"
      end
    end

    public

    # List available pitch analysis backends with detailed information
    #
    # @return [void]
    def self.list_available_backends
      backends = Converter.available_pitch_backends
      
      puts "Available pitch analysis backends:"
      if backends.empty?
        puts "  None found. Install aubio or sonic-annotator."
      else
        backends.each do |backend|
          status = case backend
                  when :aubio
                    "✓ Aubio - Fast, accurate, excellent for speech (recommended for most use cases)"
                  when :sonic_annotator  
                    "✓ Sonic Annotator - Research-grade analysis with comprehensive prosodic metrics"
                  else
                    "✓ #{backend}"
                  end
          puts "  #{status}"
        end
      end
      
      puts "\nBackend Features:"
      puts "  Aubio:"
      puts "    • YIN pitch tracking algorithm"
      puts "    • Fast processing, low memory usage"
      puts "    • Excellent for production pipelines"
      puts "    • Speech-optimized frequency analysis"
      puts ""
      puts "  Sonic Annotator:"
      puts "    • pYIN probabilistic pitch tracking"
      puts "    • Advanced tempo and rhythm analysis"
      puts "    • Multiple simultaneous feature extraction"
      puts "    • Research-grade accuracy with confidence measures"
      puts "    • Extensible plugin ecosystem"
      puts ""
      puts "Installation:"
      puts "  Aubio: apt-get install aubio-tools (Linux) or brew install aubio (macOS)"
      puts "  Sonic Annotator: https://vamp-plugins.org/sonic-annotator/"
      puts "    • Also install Vamp plugins: pyin, vamp-example-plugins"
      puts "    • macOS: brew install sonic-visualiser (includes sonic-annotator)"
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
          --verbose              Show analysis information
          --list-backends        Show available pitch analysis backends
          --help                Show this help
          
        Patterns:
          deliberate             1.0s segments, 350ms pauses (default)
          rapid                  0.6s segments, 200ms pauses  
          contemplative          1.4s segments, 500ms pauses
          
        Providers (via RubyLLM):
          openai                OpenAI GPT models (requires OPENAI_API_KEY)
          anthropic             Anthropic Claude models (requires ANTHROPIC_API_KEY)
          ollama                Local Ollama models
          
        Pitch Backends:
          aubio                 Fast, accurate, recommended for production use
          sonic_annotator       Research-grade with comprehensive prosodic analysis
          
        Audio Analysis:
          Requires SoX and a pitch analysis backend (aubio or sonic-annotator)
          Supported formats: WAV, MP3, FLAC, etc. (anything SoX can read)
          
        Backend Selection Guide:
          • Use aubio for: Production pipelines, fast processing, speech applications
          • Use sonic_annotator for: Research, detailed prosodic analysis, academic work
          
        Examples:
          # List available pitch backends and their features
          #{$0} --list-backends
          
          # Basic text conversion
          echo "Hello world" | #{$0}
          
          # Use predefined pattern
          #{$0} --pattern=rapid --provider=anthropic input.txt
          
          # Fast analysis with aubio (recommended for most use cases)
          #{$0} --audio=voice_sample.wav --pitch-backend=aubio input.txt
          
          # Comprehensive research-grade analysis with sonic-annotator
          #{$0} --audio=speaker.wav --pitch-backend=sonic_annotator input.txt
          
          # Analyze audio only with detailed metrics
          #{$0} --audio=voice_sample.wav --pitch-backend=sonic_annotator --analyze-only --verbose
          
          # Compare backends on same audio
          #{$0} --audio=test.wav --pitch-backend=aubio --analyze-only > aubio_analysis.txt
          #{$0} --audio=test.wav --pitch-backend=sonic_annotator --analyze-only > sonic_analysis.txt
          
          # Full pipeline with research-grade analysis
          #{$0} --audio=speaker.wav --pitch-backend=sonic_annotator --provider=anthropic --model=claude-3-sonnet text.txt
      USAGE
    end
  end
end