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
      load_prompts
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

    # Get LLM timeout
    #
    # @return [Integer] timeout in seconds
    def llm_timeout
      get(:llm_timeout, 30)
    end

    # Get analysis timeout
    #
    # @return [Integer] timeout in seconds
    def analysis_timeout
      get(:analysis_timeout, 60)
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

    # Check if speech pattern analysis is enabled
    #
    # @return [Boolean] true if speech pattern analysis is enabled
    def speech_pattern_analysis_enabled?
      get(:enable_speech_pattern_analysis, false)
    end

    # Check if speech pattern rewriting is enabled
    #
    # @return [Boolean] true if pattern-based text rewriting is enabled
    def speech_pattern_rewriting_enabled?
      get(:speech_pattern_rewriting, false)
    end

    # Get pattern analysis timeout
    #
    # @return [Integer] timeout in seconds
    def pattern_analysis_timeout
      get(:pattern_analysis_timeout, 120)
    end

    # Get speech pattern rewrite strategy
    #
    # @return [String] rewrite strategy (rhythm, stress, intonation, hybrid, comprehensive)
    def rewrite_strategy
      get(:rewrite_strategy, 'hybrid')
    end

    # Get pattern rewrite aggressiveness level
    #
    # @return [String] aggressiveness level (conservative, medium, aggressive)
    def pattern_rewrite_aggressiveness
      get(:pattern_rewrite_aggressiveness, 'medium')
    end

    # Get pattern meaning preservation threshold
    #
    # @return [Float] threshold value (0.0-1.0)
    def pattern_meaning_threshold
      get(:pattern_meaning_threshold, 0.85)
    end

    # Check if emotional detection is enabled
    #
    # @return [Boolean] true if emotional pattern analysis is enabled
    def emotional_detection_enabled?
      get(:enable_emotional_detection, true)
    end

    # Check if detailed pattern analysis is enabled
    #
    # @return [Boolean] true if detailed analysis features are enabled
    def detailed_pattern_analysis_enabled?
      get(:detailed_pattern_analysis, true)
    end

    # Get rhythm sensitivity level
    #
    # @return [Float] sensitivity level (0.1-1.0)
    def rhythm_sensitivity
      get(:rhythm_sensitivity, 0.7)
    end

    # Get stress detection threshold
    #
    # @return [Float] threshold value (0.0-1.0)
    def stress_detection_threshold
      get(:stress_detection_threshold, 0.6)
    end

    # Get intonation smoothing factor
    #
    # @return [Float] smoothing factor (0.0-1.0)
    def intonation_smoothing
      get(:intonation_smoothing, 0.3)
    end

    # Check if iterative pattern refinement is enabled
    #
    # @return [Boolean] true if iterative refinement is enabled
    def iterative_pattern_refinement_enabled?
      get(:iterative_pattern_refinement, true)
    end

    # Get maximum rewrite iterations
    #
    # @return [Integer] maximum number of iterations
    def max_rewrite_iterations
      get(:max_rewrite_iterations, 3)
    end

    # Get speech pattern extractor options
    #
    # @return [Hash] options for SpeechPatternExtractor
    def speech_pattern_extractor_options
      {
        detailed_analysis: detailed_pattern_analysis_enabled?,
        emotional_detection: emotional_detection_enabled?,
        rhythm_sensitivity: rhythm_sensitivity,
        stress_detection_threshold: stress_detection_threshold,
        intonation_smoothing: intonation_smoothing
      }
    end

    # Get speech pattern rewriter options
    #
    # @return [Hash] options for SpeechPatternRewriter
    def speech_pattern_rewriter_options
      {
        rewrite_strategy: rewrite_strategy,
        preserve_meaning: true,
        meaning_threshold: pattern_meaning_threshold,
        detailed_logging: true,
        max_iterations: max_rewrite_iterations,
        iterative_refinement: iterative_pattern_refinement_enabled?,
        timeout: pattern_analysis_timeout
      }
    end

    # Get ElevenLabs voice ID (supports both elevenlabs_voice and elevenlabs_voice_id)
    # Prioritizes elevenlabs_voice_id over elevenlabs_voice for backward compatibility
    #
    # @return [String, nil] voice ID or nil if not set
    def elevenlabs_voice_id
      # Check if elevenlabs_voice_id was explicitly set (not just from defaults)
      voice_id = @config.fetch('elevenlabs_voice_id', default: nil)
      voice = @config.fetch('elevenlabs_voice', default: nil)

      # If voice_id was set via CLI/env and differs from default, use it
      # Otherwise fall back to elevenlabs_voice if set
      if voice_id && voice_id != 'L0Dsvb3SLTyegXwtm47J' # default value
        voice_id
      elsif voice && voice != 'L0Dsvb3SLTyegXwtm47J' # default value
        voice
      else
        voice_id # return default if nothing else was set
      end
    end

    # Get a prompt template from the configuration
    #
    # @param key [Symbol, String] prompt key
    # @return [String, nil] prompt template
    def prompt(key)
      get(key)
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
        @config.set(:model, value: 'gemini-2.5-flash')
        @config.set(:pitch_backend, value: 'aubio')
        @config.set(:llm_timeout, value: 30)
        @config.set(:analysis_timeout, value: 60)
        @config.set(:spectrogram_dir, value: './spectrograms')
        @config.set(:verbose, value: false)
      end
    end

    # Load prompts from prompts.yml file
    #
    # @return [void]
    def load_prompts
      prompts_file = @config_dir + 'prompts.yml'
      @config.read(prompts_file.to_s) if prompts_file.exist?
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
      @config.set_from_env(:elevenlabs_voice_id)
      @config.set_from_env(:elevenlabs_stability)
      @config.set_from_env(:elevenlabs_similarity_boost)
      @config.set_from_env(:elevenlabs_use_phonemes)
      @config.set_from_env(:elevenlabs_dictionary_ids)
      @config.set_from_env(:enable_rephrasing)
      @config.set_from_env(:rephrasing_aggressiveness)
      @config.set_from_env(:preserve_meaning_threshold)
      @config.set_from_env(:rephrasing_timeout)
      @config.set_from_env(:enable_speech_pattern_analysis)
      @config.set_from_env(:speech_pattern_rewriting)
      @config.set_from_env(:pattern_analysis_timeout)
      @config.set_from_env(:rewrite_strategy)
      @config.set_from_env(:pattern_rewrite_aggressiveness)
      @config.set_from_env(:pattern_meaning_threshold)
      @config.set_from_env(:enable_emotional_detection)
      @config.set_from_env(:detailed_pattern_analysis)
      @config.set_from_env(:rhythm_sensitivity)
      @config.set_from_env(:stress_detection_threshold)
      @config.set_from_env(:intonation_smoothing)
      @config.set_from_env(:iterative_pattern_refinement)
      @config.set_from_env(:max_rewrite_iterations)

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
        when /^--elevenlabs-voice-id=(.+)$/
          config_hash[:elevenlabs_voice_id] = ::Regexp.last_match(1)
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
        when '--enable-speech-patterns'
          config_hash[:enable_speech_pattern_analysis] = true
        when '--disable-speech-patterns'
          config_hash[:enable_speech_pattern_analysis] = false
        when '--enable-pattern-rewriting'
          config_hash[:speech_pattern_rewriting] = true
        when '--disable-pattern-rewriting'
          config_hash[:speech_pattern_rewriting] = false
        when /^--pattern-analysis-timeout=(.+)$/
          config_hash[:pattern_analysis_timeout] = ::Regexp.last_match(1).to_i
        when /^--rewrite-strategy=(.+)$/
          config_hash[:rewrite_strategy] = ::Regexp.last_match(1)
        when /^--pattern-rewrite-aggressiveness=(.+)$/
          config_hash[:pattern_rewrite_aggressiveness] = ::Regexp.last_match(1)
        when /^--pattern-meaning-threshold=(.+)$/
          config_hash[:pattern_meaning_threshold] = ::Regexp.last_match(1).to_f
        when '--enable-emotional-detection'
          config_hash[:enable_emotional_detection] = true
        when '--disable-emotional-detection'
          config_hash[:enable_emotional_detection] = false
        when '--enable-detailed-analysis'
          config_hash[:detailed_pattern_analysis] = true
        when '--disable-detailed-analysis'
          config_hash[:detailed_pattern_analysis] = false
        when /^--rhythm-sensitivity=(.+)$/
          config_hash[:rhythm_sensitivity] = ::Regexp.last_match(1).to_f
        when /^--stress-threshold=(.+)$/
          config_hash[:stress_detection_threshold] = ::Regexp.last_match(1).to_f
        when /^--intonation-smoothing=(.+)$/
          config_hash[:intonation_smoothing] = ::Regexp.last_match(1).to_f
        when '--enable-iterative-refinement'
          config_hash[:iterative_pattern_refinement] = true
        when '--disable-iterative-refinement'
          config_hash[:iterative_pattern_refinement] = false
        when /^--max-rewrite-iterations=(.+)$/
          config_hash[:max_rewrite_iterations] = ::Regexp.last_match(1).to_i
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
