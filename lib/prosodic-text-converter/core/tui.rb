# frozen_string_literal: true

begin
  require 'tty-prompt'
rescue LoadError
  puts "Error: Missing required gem 'tty-prompt'. Please run: bundle install"
  exit 1
end

require 'tty-config'
require 'fileutils'
require 'pathname'
require_relative 'config'
require_relative 'converter'

module ProsodicTextConverter
  # TUI (Terminal User Interface) for interactive configuration and operation
  #
  # Provides a user-friendly interface for:
  # - Setting up API keys and environment variables
  # - Configuring application options
  # - Selecting output directories
  # - Running the conversion process
  class TUI
    include Logging

    def initialize
      @prompt = TTY::Prompt.new
      @config = Config.new
    end

    # Main entry point for the TUI
    def run
      logger.info('Starting TUI interface')

      display_welcome

      # Check and setup environment if needed
      setup_environment_if_needed

      # Collect user preferences
      options = collect_user_options

      # Setup output directory
      output_dir = setup_output_directory
      options[:output_dir] = output_dir

      # Confirm and execute
      if confirm_execution(options)
        execute_with_options(options)
      else
        @prompt.say('Operation cancelled.')
      end
    end

    private

    def display_welcome
      @prompt.say('')
      @prompt.say('🎤 Prosodic Text Converter - Interactive Setup', color: :cyan)
      @prompt.say('=' * 50, color: :cyan)
      @prompt.say('')
    end

    # Check if environment setup is needed and prompt accordingly
    def setup_environment_if_needed
      env_file = Pathname.new('.env')

      if env_file.exist?
        setup_environment_variables if @prompt.yes?('Update existing .env configuration?', default: false)
      elsif @prompt.yes?('No .env file found. Would you like to set up API keys?', color: :yellow)
        setup_environment_variables
      end
    end

    # Setup environment variables interactively
    def setup_environment_variables
      @prompt.say("\n📝 Setting up API keys and environment variables", color: :green)

      env_config = {}

      # LLM Provider API Keys
      @prompt.say("\n🤖 Language Model API Keys (at least one required):", color: :blue)

      env_config['OPENROUTER_API_KEY'] = @prompt.ask('Open Router API Key:',
                                                     default: ENV['OPENROUTER_API_KEY'],
                                                     help: 'Required for Open Router models',
                                                     echo: false) { |q| q.required(false) }

      env_config['OPENAI_API_KEY'] = @prompt.ask('OpenAI API Key:',
                                                 default: ENV['OPENAI_API_KEY'],
                                                 help: 'Required for GPT models',
                                                 echo: false) { |q| q.required(false) }

      env_config['ANTHROPIC_API_KEY'] = @prompt.ask('Anthropic API Key:',
                                                    default: ENV['ANTHROPIC_API_KEY'],
                                                    help: 'Required for Claude models',
                                                    echo: false) { |q| q.required(false) }

      env_config['GEMINI_API_KEY'] = @prompt.ask('Google Gemini API Key:',
                                                 default: ENV['GEMINI_API_KEY'],
                                                 help: 'Required for Gemini models',
                                                 echo: false) { |q| q.required(false) }

      # Optional services
      @prompt.say("\n🔊 Optional Services:", color: :blue)

      env_config['ELEVENLABS_API_KEY'] = @prompt.ask('ElevenLabs API Key:',
                                                     default: ENV['ELEVENLABS_API_KEY'],
                                                     help: 'For speech synthesis',
                                                     echo: false) { |q| q.required(false) }

      # System configuration
      @prompt.say("\n⚙️  System Configuration:", color: :blue)

      env_config['PROSODIC_PITCH_BACKEND'] = @prompt.select('Default pitch backend:',
                                                            %w[aubio sonic_annotator],
                                                            default: ENV['PROSODIC_PITCH_BACKEND'] || 'aubio',
                                                            help: 'Choose your preferred audio analysis backend')

      env_config['PROSODIC_LOG_LEVEL'] = @prompt.select('Log level:',
                                                        %w[DEBUG INFO WARN ERROR FATAL],
                                                        default: ENV['PROSODIC_LOG_LEVEL'] || 'INFO',
                                                        help: 'Set logging verbosity')

      env_config['PROSODIC_LOG_DIR'] = @prompt.ask('Log directory:',
                                                   default: ENV['PROSODIC_LOG_DIR'] || './log',
                                                   help: 'Directory for log files')

      # Write .env file
      write_env_file(env_config)

      @prompt.say("\n✅ Environment configuration saved to .env", color: :green)
    end

    # Write environment configuration to .env file
    def write_env_file(config)
      env_content = []
      env_content << '# API Keys for Language Model Providers'
      env_content << '# Generated by Prosodic Text Converter TUI'
      env_content << ''

      config.each do |key, value|
        next if value.nil? || value.strip.empty?

        env_content << "#{key}=#{value}"
      end

      File.write('.env', env_content.join("\n"))
    end

    # Collect user options for the conversion process
    def collect_user_options
      @prompt.say("\n🔧 Conversion Options", color: :green)

      options = {}

      # Input source
      input_choice = @prompt.select('How would you like to provide input?', [
                                      { name: 'Text file', value: :file },
                                      { name: 'Type text directly', value: :direct },
                                      { name: 'Read from clipboard', value: :clipboard }
                                    ])

      case input_choice
      when :file
        options[:input_file] = @prompt.ask('Input file path:') do |q|
          q.required(true)
          q.validate(->(path) { File.exist?(path) })
          q.messages[:valid?] = 'File does not exist'
        end
      when :direct
        @prompt.say('Enter your text (press Enter twice when done):')
        input_lines = []
        loop do
          line = @prompt.ask('')
          break if line.nil?
          break if line.empty? && !input_lines.empty?

          input_lines << line
        end
        options[:input_text] = input_lines.join("\n")
      when :clipboard
        begin
          require 'clipboard'
          options[:input_text] = Clipboard.paste
          @prompt.say('✅ Text loaded from clipboard', color: :green)
        rescue LoadError
          @prompt.error('Clipboard gem not available. Please install with: gem install clipboard')
          return collect_user_options
        end
      end

      # Audio analysis
      if @prompt.yes?('Use audio analysis for prosodic patterns?', default: false)
        options[:audio_file] = @prompt.ask('Audio file path:') do |q|
          q.required(true)
          q.validate(->(path) { File.exist?(path) })
          q.messages[:valid?] = 'Audio file does not exist'
        end

        options[:pitch_backend] = @prompt.select('Pitch analysis backend:',
                                                 get_available_backends,
                                                 default: 'aubio',
                                                 help: 'aubio: fast, sonic_annotator: research-grade')
      else
        # Use predefined pattern
        patterns = {
          'deliberate' => '1.0s segments, 350ms pauses (default)',
          'rapid' => '0.6s segments, 200ms pauses',
          'contemplative' => '1.4s segments, 500ms pauses'
        }

        pattern_choices = patterns.map { |k, v| { name: "#{k.capitalize} - #{v}", value: k } }
        options[:pattern_name] = @prompt.select('Select prosodic pattern:', pattern_choices, default: 'deliberate')
      end

      # LLM Configuration
      @prompt.say("\n🤖 Language Model Configuration", color: :blue)

      available_providers = get_available_providers
      options[:provider] = @prompt.select('LLM Provider:', available_providers, default: @config.get(:provider))

      case options[:provider]
      when 'openrouter'
        models = [
          'openai/gpt-4o',
          'anthropic/claude-3.5-sonnet',
          'google/gemini-2.5-flash',
          'openai/gpt-4-turbo',
          'anthropic/claude-3-haiku',
          'meta-llama/llama-3.1-70b-instruct',
          'mistralai/mistral-7b-instruct'
        ]
        options[:model] = @prompt.select('OpenRouter Model:', models, default: 'openai/gpt-4o')
      when 'openai'
        models = %w[gpt-4 gpt-4-turbo gpt-3.5-turbo]
        options[:model] = @prompt.select('OpenAI Model:', models, default: 'gpt-4')
      when 'anthropic'
        models = %w[claude-3-opus claude-3-sonnet claude-3-haiku]
        options[:model] = @prompt.select('Anthropic Model:', models, default: 'claude-3-sonnet')
      when 'gemini'
        models = %w[gemini-2.5-flash gemini-1.5-pro gemini-1.5-flash]
        options[:model] = @prompt.select('Gemini Model:', models, default: 'gemini-2.5-flash')
      when 'ollama'
        options[:model] = @prompt.ask('Ollama Model:', default: 'llama2')
      else
        # Default model for any provider
        options[:model] = 'gemini-2.5-flash'
      end

      # Output options
      @prompt.say("\n📤 Output Options", color: :blue)

      options[:output_format] = @prompt.select('Output format:', %w[ssml xml plain], default: 'ssml')

      # ElevenLabs synthesis
      if @prompt.yes?('Generate speech with ElevenLabs?', default: false)
        if ENV['ELEVENLABS_API_KEY']
          voices = get_elevenlabs_voices
          options[:elevenlabs_voice_id] = @prompt.select('ElevenLabs voice:', voices)
          options[:elevenlabs_model] = @prompt.select('ElevenLabs model:',
                                                      %w[eleven_monolingual_v1 eleven_multilingual_v1],
                                                      default: 'eleven_monolingual_v1')
        else
          @prompt.error('ElevenLabs API key not configured')
        end
      end

      # Advanced options
      if @prompt.yes?('Configure advanced options?', default: false)
        options[:verbose] = @prompt.yes?('Verbose output?', default: false)

        # Rephrasing options
        @prompt.say("\n🔄 Text Rephrasing (SFL-based prosodic optimization):", color: :cyan)
        options[:enable_rephrasing] = @prompt.yes?('Enable text rephrasing for better prosodic fit?',
                                                   default: @config.rephrasing_enabled?)

        if options[:enable_rephrasing]
          options[:rephrasing_aggressiveness] = @prompt.select('Rephrasing aggressiveness:',
                                                               [
                                                                 {
                                                                   name: 'Conservative - Minimal changes, preserve structure', value: 'conservative'
                                                                 },
                                                                 { name: 'Medium - Moderate restructuring for prosody',
                                                                   value: 'medium' },
                                                                 {
                                                                   name: 'Aggressive - Significant changes for optimal fit', value: 'aggressive'
                                                                 }
                                                               ],
                                                               default: @config.rephrasing_aggressiveness)

          options[:preserve_meaning_threshold] = @prompt.ask('Meaning preservation threshold (0.0-1.0):',
                                                             default: @config.preserve_meaning_threshold, convert: :float) do |q|
            q.validate(->(val) { val >= 0.0 && val <= 1.0 })
            q.messages[:valid?] = 'Must be between 0.0 and 1.0'
          end

          options[:rephrasing_timeout] = @prompt.ask('Rephrasing timeout (seconds):',
                                                     default: @config.rephrasing_timeout, convert: :int)
        end

        # Other timeouts
        options[:llm_timeout] = @prompt.ask('LLM timeout (seconds):',
                                            default: @config.get(:llm_timeout), convert: :int)
        options[:analysis_timeout] = @prompt.ask('Analysis timeout (seconds):',
                                                 default: @config.get(:analysis_timeout), convert: :int)
      end

      options
    end

    # Setup output directory with creation if needed
    def setup_output_directory
      @prompt.say("\n📁 Output Directory Setup", color: :green)

      output_dir = @prompt.ask('Output directory:',
                               default: './output') do |q|
        q.required(true)
      end

      output_path = Pathname.new(output_dir)

      unless output_path.exist?
        unless @prompt.yes?("Directory '#{output_dir}' doesn't exist. Create it?", color: :yellow)
          return setup_output_directory
        end

        begin
          FileUtils.mkdir_p(output_path)
          @prompt.say("✅ Created directory: #{output_path.realpath}", color: :green)
        rescue StandardError => e
          @prompt.error("Failed to create directory: #{e.message}")
          return setup_output_directory
        end

      end

      output_path.to_s
    end

    # Confirm execution with summary
    def confirm_execution(options)
      @prompt.say("\n📋 Configuration Summary", color: :cyan)
      @prompt.say('=' * 30, color: :cyan)

      options.each do |key, value|
        next if value.nil? || value == []

        display_value = case key
                        when :input_text
                          '[Text content]'
                        when :input_file
                          File.basename(value.to_s)
                        else
                          value.to_s
                        end
        @prompt.say("#{key.to_s.humanize}: #{display_value}")
      end

      @prompt.say('')
      @prompt.yes?('Proceed with conversion?', color: :green)
    end

    # Execute the conversion with collected options
    def execute_with_options(options)
      @prompt.say("\n🚀 Starting conversion...", color: :green)

      begin
        # Convert options to CLI args format
        cli_args = build_cli_args(options)

        # Create config from args
        config = Config.from_cli_args(cli_args)

        # Setup input text
        input_text = options[:input_text] || (options[:input_file] ? File.read(options[:input_file]) : nil)

        # Validate required parameters
        provider = config.get(:provider)
        model = config.get(:model)

        raise ArgumentError, 'Provider is required' if provider.nil? || provider.empty?

        raise ArgumentError, 'Model is required' if model.nil? || model.empty?

        raise ArgumentError, 'Input text is required' if input_text.nil? || input_text.strip.empty?

        # Execute conversion
        converter_options = {
          provider: provider.to_sym,
          model: model.to_s
        }

        # Add pattern only if provided
        converter_options[:pattern] = config.predefined_pattern if config.predefined_pattern

        # Add pitch backend only if provided
        converter_options[:pitch_backend] = config.get(:pitch_backend).to_sym if config.get(:pitch_backend)

        @prompt.say("Creating converter with: #{converter_options.inspect}", color: :blue) if options[:verbose]
        converter = Converter.new(**converter_options)

        result = if options[:audio_file]
                   converter.convert_with_audio_analysis(input_text, options[:audio_file])
                 else
                   converter.convert(input_text)
                 end

        # Save output
        output_file = File.join(options[:output_dir],
                                "converted_#{Time.now.strftime('%Y%m%d_%H%M%S')}.#{options[:output_format] || 'ssml'}")
        File.write(output_file, result[:ssml_output] || result.to_s)

        @prompt.say("\n✅ Conversion completed!", color: :green)
        @prompt.say("Output saved to: #{output_file}", color: :blue)

        # Handle ElevenLabs synthesis if requested
        synthesize_speech(result[:ssml_output], options) if options[:elevenlabs_voice_id] && result[:ssml_output]
      rescue StandardError => e
        logger.error("TUI execution failed: #{e.message}")
        logger.debug("Backtrace: #{e.backtrace.join("\n")}")
        @prompt.error("Conversion failed: #{e.message}")

        # Show debugging info if verbose
        if options[:verbose]
          @prompt.say("\nDebugging information:", color: :yellow)
          @prompt.say("Provider: #{config.get(:provider)}")
          @prompt.say("Model: #{config.get(:model)}")
          @prompt.say("Error class: #{e.class}")
          @prompt.say("Full error: #{e.message}")
        end
      end
    end

    # Build CLI arguments array from options hash
    def build_cli_args(options)
      args = []

      args << "--pattern=#{options[:pattern_name]}" if options[:pattern_name]
      args << "--audio=#{options[:audio_file]}" if options[:audio_file]
      args << "--pitch-backend=#{options[:pitch_backend]}" if options[:pitch_backend]
      args << "--provider=#{options[:provider]}" if options[:provider]
      args << "--model=#{options[:model]}" if options[:model]
      args << "--elevenlabs-voice-id=#{options[:elevenlabs_voice_id]}" if options[:elevenlabs_voice_id]
      args << "--elevenlabs-model=#{options[:elevenlabs_model]}" if options[:elevenlabs_model]
      args << '--verbose' if options[:verbose]
      args << "--llm-timeout=#{options[:llm_timeout]}" if options[:llm_timeout]
      args << "--analysis-timeout=#{options[:analysis_timeout]}" if options[:analysis_timeout]

      # Rephrasing options
      if options[:enable_rephrasing]
        args << '--rephrase'
        if options[:rephrasing_aggressiveness]
          args << "--rephrasing-aggressiveness=#{options[:rephrasing_aggressiveness]}"
        end
        if options[:preserve_meaning_threshold]
          args << "--preserve-meaning-threshold=#{options[:preserve_meaning_threshold]}"
        end
        args << "--rephrasing-timeout=#{options[:rephrasing_timeout]}" if options[:rephrasing_timeout]
      else
        args << '--no-rephrase'
      end

      args << options[:input_file] if options[:input_file]

      args
    end

    # Get available pitch analysis backends
    def get_available_backends
      Converter.available_pitch_backends.map(&:to_s)
    rescue StandardError
      %w[aubio]
    end

    # Get available LLM providers based on API keys
    def get_available_providers
      providers = []
      if ENV['OPENAI_API_KEY'] && !ENV['OPENAI_API_KEY'].empty? && ENV['OPENAI_API_KEY'] != 'your-openai-api-key-here'
        providers << 'openai'
      end
      if ENV['ANTHROPIC_API_KEY'] && !ENV['ANTHROPIC_API_KEY'].empty? && ENV['ANTHROPIC_API_KEY'] != 'your-anthropic-api-key-here'
        providers << 'anthropic'
      end
      if ENV['GEMINI_API_KEY'] && !ENV['GEMINI_API_KEY'].empty? && ENV['GEMINI_API_KEY'] != 'your-gemini-api-key-here'
        providers << 'gemini'
      end
      if ENV['OPENROUTER_API_KEY'] && !ENV['OPENROUTER_API_KEY'].empty? && ENV['OPENROUTER_API_KEY'] != 'your-openrouter-api-key-here'
        providers << 'openrouter'
      end
      providers << 'ollama' # Always available for local models

      # If no valid providers, show all options but warn user
      if providers.empty? || providers == ['ollama']
        @prompt.warn('⚠️  No API keys configured!')
        @prompt.say('Please either:')
        @prompt.say('  1. Set up API keys via the environment setup')
        @prompt.say('  2. Use Ollama for local models')
        @prompt.say('  3. Set environment variables manually (OPENAI_API_KEY, GEMINI_API_KEY, OPENROUTER_API_KEY, etc.)')
        return %w[ollama gemini openai anthropic openrouter]
      end

      providers
    end

    # Get ElevenLabs voices
    def get_elevenlabs_voices
      return %w[Aria Neha Bill] # Default voices if API call fails

      begin
        require_relative '../audio/speech_synthesizer'
        synthesizer = SpeechSynthesizer.new(provider: :elevenlabs)
        voices = synthesizer.get_voices
        voices.map { |v| { name: "#{v['name']} (#{v['voice_id']})", value: v['voice_id'] } }
      rescue StandardError => e
        logger.warn("Failed to fetch ElevenLabs voices: #{e.message}")
        %w[Aria Neha Bill]
      end
    end

    # Synthesize speech with ElevenLabs
    def synthesize_speech(ssml_text, options)
      @prompt.say("\n🔊 Synthesizing speech...", color: :blue)

      begin
        require_relative '../audio/speech_synthesizer'
        synthesizer = SpeechSynthesizer.new(provider: :elevenlabs)

        audio_data = synthesizer.synthesize_ssml(
          ssml_text,
          voice: options[:elevenlabs_voice_id],
          model_id: options[:elevenlabs_model]
        )

        # Ensure output directory exists
        FileUtils.mkdir_p(options[:output_dir]) unless Dir.exist?(options[:output_dir])

        audio_file = File.join(options[:output_dir], "speech_#{Time.now.strftime('%Y%m%d_%H%M%S')}.mp3")
        synthesizer.save_audio(audio_data, audio_file)

        @prompt.say("🎵 Speech saved to: #{audio_file}", color: :green)
      rescue StandardError => e
        logger.error("Speech synthesis failed: #{e.message}")
        @prompt.error("Speech synthesis failed: #{e.message}")
      end
    end
  end
end

# String extension for humanizing keys
class String
  def humanize
    split('_').map(&:capitalize).join(' ')
  end
end
