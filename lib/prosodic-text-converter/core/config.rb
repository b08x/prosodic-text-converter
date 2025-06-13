# frozen_string_literal: true

require 'tty-config'
require 'pathname'

module ProsodicTextConverter
  # Centralized configuration management using tty-config
  #
  # Loads configuration from:
  # 1. Default YAML file (config/defaults.yml)
  # 2. Environment variables (prefixed with PTC_)
  # 3. CLI arguments (highest precedence)
  #
  # @example Basic usage
  #   config = Config.new
  #   config.set(:provider, 'openai')
  #   puts config.get(:provider)
  #
  # @example With CLI arguments
  #   config = Config.from_cli_args(['--provider=anthropic', '--model=claude-3-sonnet'])
  #   puts config.get(:provider) # => 'anthropic'
  class Config
    # @return [TTY::Config] the underlying config object
    attr_reader :config

    # Initialize configuration with defaults
    #
    # @param config_dir [String, Pathname] directory containing config files
    def initialize(config_dir: nil)
      @config_dir = config_dir || default_config_dir
      @config = TTY::Config.new

      # Set default configuration namespace and environment prefix
      @config.filename = 'prosodic-text-converter'
      @config.env_prefix = 'PTC'
      @config.append_path(@config_dir.to_s) if @config_dir.exist?

      load_defaults
      load_environment_variables
    end

    # Create configuration from CLI arguments
    #
    # @param args [Array<String>] command line arguments
    # @param config_dir [String, Pathname] directory containing config files
    # @return [Config] configured instance
    def self.from_cli_args(args, config_dir: nil)
      config = new(config_dir: config_dir)
      config.load_cli_args(args)
      config
    end

    # Get configuration value
    #
    # @param key [Symbol, String] configuration key
    # @param default [Object] default value if key not found
    # @return [Object] configuration value
    def get(key, default = nil)
      @config.fetch(key.to_s, default: default)
    end

    # Set configuration value
    #
    # @param key [Symbol, String] configuration key
    # @param value [Object] configuration value
    # @return [Object] the set value
    def set(key, value)
      @config.set(key.to_s, value: value)
      value
    end

    # Load CLI arguments and override existing configuration
    #
    # @param args [Array<String>] command line arguments
    # @return [void]
    def load_cli_args(args)
      parse_cli_arguments(args).each do |key, value|
        set(key, value)
      end
    end

    # Get all configuration as a hash
    #
    # @return [Hash] all configuration values
    def to_hash
      @config.to_h
    end

    # Get input files from configuration
    #
    # @return [Array<String>] list of input files
    def input_files
      get(:input_files, [])
    end

    # Get the first input file
    #
    # @return [String, nil] first input file or nil
    def input_file
      input_files.first
    end

    # Check if verbose mode is enabled
    #
    # @return [Boolean] true if verbose mode
    def verbose?
      get(:verbose, false)
    end

    # Check if analyze-only mode is enabled
    #
    # @return [Boolean] true if analyze-only mode
    def analyze_only?
      get(:analyze_only, false)
    end

    # Check if health check is requested
    #
    # @return [Boolean] true if health check requested
    def health_check?
      get(:health_check, false)
    end

    # Check if backend listing is requested
    #
    # @return [Boolean] true if backend listing requested
    def list_backends?
      get(:list_backends, false)
    end

    # Check if voice listing is requested
    #
    # @return [Boolean] true if voice listing requested
    def list_voices?
      get(:list_voices, false)
    end

    # Get predefined pattern if specified
    #
    # @return [Hash, nil] predefined pattern or nil
    def predefined_pattern
      pattern_name = get(:pattern_name)
      return nil unless pattern_name

      require_relative 'converter'
      Converter.predefined_patterns[pattern_name.to_sym]
    end

    # Check if rephrasing is enabled
    #
    # @return [Boolean] true if rephrasing is enabled
    def rephrasing_enabled?
      get(:enable_rephrasing, false)
    end

    # Get rephrasing aggressiveness level
    #
    # @return [String] aggressiveness level (conservative, medium, aggressive)
    def rephrasing_aggressiveness
      get(:rephrasing_aggressiveness, 'medium')
    end

    # Get meaning preservation threshold
    #
    # @return [Float] threshold value (0.0-1.0)
    def preserve_meaning_threshold
      get(:preserve_meaning_threshold, 0.8)
    end

    # Get rephrasing timeout
    #
    # @return [Integer] timeout in seconds
    def rephrasing_timeout
      get(:rephrasing_timeout, 45)
    end

    private

    # Get default configuration directory
    #
    # @return [Pathname] path to config directory
    def default_config_dir
      Pathname.new(__dir__).parent.parent.parent + 'config'
    end

    # Load default configuration from YAML file
    #
    # @return [void]
    def load_defaults
      defaults_file = @config_dir + 'defaults.yml'

      if defaults_file.exist?
        @config.read(defaults_file.to_s)
      else
        # Set some sensible defaults if no file exists
        @config.set(:provider, value: 'gemini')
        @config.set(:model, value: 'gemini-2.0-flash')
        @config.set(:pitch_backend, value: 'aubio')
        @config.set(:llm_timeout, value: 30)
        @config.set(:analysis_timeout, value: 60)
        @config.set(:spectrogram_dir, value: './spectrograms')
        @config.set(:verbose, value: false)
      end
    end

    # Load environment variables with PTC_ prefix
    #
    # @return [void]
    def load_environment_variables
      # Set up environment variable mappings using TTY::Config's set_from_env
      @config.set_from_env(:provider)
      @config.set_from_env(:model)
      @config.set_from_env(:pitch_backend)
      @config.set_from_env(:llm_timeout)
      @config.set_from_env(:analysis_timeout)
      @config.set_from_env(:spectrogram_dir)
      @config.set_from_env(:verbose)
      @config.set_from_env(:elevenlabs_model)
      @config.set_from_env(:elevenlabs_model_id)
      @config.set_from_env(:elevenlabs_voice)
      @config.set_from_env(:elevenlabs_stability)
      @config.set_from_env(:elevenlabs_similarity_boost)
      @config.set_from_env(:elevenlabs_use_phonemes)
      @config.set_from_env(:elevenlabs_dictionary_ids)
      @config.set_from_env(:enable_rephrasing)
      @config.set_from_env(:rephrasing_aggressiveness)
      @config.set_from_env(:preserve_meaning_threshold)
      @config.set_from_env(:rephrasing_timeout)

      # Also load API keys for LLM providers  
      @config.set_from_env(:openai_api_key)
      @config.set_from_env(:anthropic_api_key)
      @config.set_from_env(:gemini_api_key)
      @config.set_from_env(:openrouter_api_key)

      # Also support legacy environment variables for backwards compatibility
      set(:provider, ENV['PROSODIC_PROVIDER']) if ENV['PROSODIC_PROVIDER']
      set(:pitch_backend, ENV['PROSODIC_PITCH_BACKEND']) if ENV['PROSODIC_PITCH_BACKEND']
    end

    # Parse CLI arguments into configuration hash
    #
    # @param args [Array<String>] command line arguments
    # @return [Hash] parsed configuration
    def parse_cli_arguments(args)
      config_hash = {}
      input_files = []

      args.each do |arg|
        case arg
        when /^--pattern=(.+)$/
          config_hash[:pattern_name] = ::Regexp.last_match(1)
        when /^--provider=(.+)$/
          config_hash[:provider] = ::Regexp.last_match(1)
        when /^--model=(.+)$/
          config_hash[:model] = ::Regexp.last_match(1)
        when /^--pitch-backend=(.+)$/
          config_hash[:pitch_backend] = ::Regexp.last_match(1)
        when /^--audio=(.+)$/
          config_hash[:audio_file] = ::Regexp.last_match(1)
        when /^--spectrogram-dir=(.+)$/
          config_hash[:spectrogram_dir] = ::Regexp.last_match(1)
        when /^--elevenlabs-voice=(.+)$/
          config_hash[:elevenlabs_voice] = ::Regexp.last_match(1)
        when /^--elevenlabs-model=(.+)$/
          config_hash[:elevenlabs_model] = ::Regexp.last_match(1)
        when /^--elevenlabs-model-id=(.+)$/
          config_hash[:elevenlabs_model_id] = ::Regexp.last_match(1)
        when /^--elevenlabs-stability=(.+)$/
          config_hash[:elevenlabs_stability] = ::Regexp.last_match(1).to_f
        when /^--elevenlabs-similarity-boost=(.+)$/
          config_hash[:elevenlabs_similarity_boost] = ::Regexp.last_match(1).to_f
        when '--elevenlabs-use-phonemes'
          config_hash[:elevenlabs_use_phonemes] = true
        when /^--elevenlabs-dictionary-ids=(.+)$/
          config_hash[:elevenlabs_dictionary_ids] = ::Regexp.last_match(1).split(',').map(&:strip)
        when /^--output=(.+)$/
          config_hash[:output_file] = ::Regexp.last_match(1)
        when /^--output-dir=(.+)$/
          config_hash[:output_dir] = ::Regexp.last_match(1)
        when '--rephrase'
          config_hash[:enable_rephrasing] = true
        when '--no-rephrase'
          config_hash[:enable_rephrasing] = false
        when /^--rephrasing-aggressiveness=(.+)$/
          config_hash[:rephrasing_aggressiveness] = ::Regexp.last_match(1)
        when /^--preserve-meaning-threshold=(.+)$/
          config_hash[:preserve_meaning_threshold] = ::Regexp.last_match(1).to_f
        when /^--rephrasing-timeout=(.+)$/
          config_hash[:rephrasing_timeout] = ::Regexp.last_match(1).to_i
        when '--verbose'
          config_hash[:verbose] = true
        when '--analyze-only'
          config_hash[:analyze_only] = true
        when '--health-check'
          config_hash[:health_check] = true
        when '--list-backends'
          config_hash[:list_backends] = true
        when '--list-voices'
          config_hash[:list_voices] = true
        when '--help'
          config_hash[:help] = true
        else
          # Non-option arguments are input files
          input_files << arg unless arg.start_with?('--')
        end
      end

      config_hash[:input_files] = input_files unless input_files.empty?
      config_hash
    end
  end
end
