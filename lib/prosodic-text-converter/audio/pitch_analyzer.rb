# frozen_string_literal: true

require 'logger'

module ProsodicTextConverter
  # Abstract interface for pitch analysis backends
  #
  # @abstract Subclasses must implement {#analyze} method
  class PitchAnalyzer
    # @return [Logger] logger instance
    attr_reader :logger

    # Initialize the pitch analyzer
    #
    # @param logger [Logger, nil] custom logger instance
    def initialize(logger: nil)
      @logger = logger || setup_logger
    end

    # Analyze audio file for pitch information
    #
    # @param audio_file [String] path to audio file
    # @return [Array<Hash>] pitch analysis data
    # @raise [NotImplementedError] must be implemented by subclasses
    def analyze(audio_file)
      raise NotImplementedError, "Subclasses must implement analyze method"
    end

    protected

    # Setup default logger
    #
    # @return [Logger] configured logger
    def setup_logger
      Logger.new($stderr).tap do |log|
        log.level = Logger::INFO
        log.formatter = proc do |severity, datetime, progname, msg|
          "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] PitchAnalyzer #{severity}: #{msg}\n"
        end
      end
    end

    # Validate audio file before analysis
    #
    # @param audio_file [String] path to audio file
    # @raise [ArgumentError] if file is invalid
    def validate_audio_file(audio_file)
      if audio_file.nil? || audio_file.strip.empty?
        error_msg = "Audio file path cannot be nil or empty"
        @logger.error(error_msg)
        raise ArgumentError, error_msg
      end
      
      unless File.exist?(audio_file)
        error_msg = "Audio file not found: #{audio_file}"
        @logger.error(error_msg)
        raise ArgumentError, error_msg
      end
      
      unless File.readable?(audio_file)
        error_msg = "Audio file not readable: #{audio_file}"
        @logger.error(error_msg)
        raise ArgumentError, error_msg
      end
    end

    public

    # Calculate pitch variation coefficient from pitch data
    #
    # @param pitch_data [Array<Hash>] pitch analysis data
    # @return [Float] pitch variation percentage (1.0-15.0)
    def calculate_pitch_variation(pitch_data)
      begin
        return 5.0 if pitch_data.empty?
        
        frequencies = pitch_data.map { |p| p[:frequency] }.reject(&:zero?)
        return 5.0 if frequencies.length < 2
        
        mean_freq = frequencies.sum / frequencies.length.to_f
        variance = frequencies.map { |f| (f - mean_freq) ** 2 }.sum / frequencies.length.to_f
        std_dev = Math.sqrt(variance)
        
        # Convert to percentage variation
        coefficient_of_variation = (std_dev / mean_freq) * 100
        result = coefficient_of_variation.clamp(1.0, 15.0)
        
        @logger.debug("Calculated pitch variation: #{result.round(2)}% (#{frequencies.length} data points)")
        result
        
      rescue StandardError => e
        @logger.warn("Error calculating pitch variation: #{e.message}, using default")
        5.0
      end
    end
  end


  # Factory for creating pitch analyzers
  #
  # @example Create an Aubio analyzer
  #   analyzer = PitchAnalyzerFactory.create(backend: :aubio)
  #
  # @example Create a Sonic Annotator analyzer
  #   analyzer = PitchAnalyzerFactory.create(backend: :sonic_annotator, step_size: 128)
  class PitchAnalyzerFactory
    # Create a pitch analyzer instance for the specified backend
    #
    # @param backend [Symbol] pitch analysis backend (:aubio or :sonic_annotator)
    # @param options [Hash] additional options passed to analyzer constructor
    # @return [PitchAnalyzer] configured pitch analyzer instance
    # @raise [ArgumentError] if backend is unknown
    def self.create(backend: :aubio, **options)
      case backend
      when :aubio
        AubioPitchAnalyzer.new(**options)
      when :sonic_annotator
        SonicAnnotatorPitchAnalyzer.new(**options)
      else
        raise ArgumentError, "Unknown pitch analyzer backend: #{backend}"
      end
    end

    # Get list of available pitch analysis backends on the system
    #
    # @return [Array<Symbol>] list of available backends (e.g., [:aubio, :sonic_annotator])
    def self.available_backends
      backends = []
      
      # Check for FFI-based aubio (always available if gem is installed)
      begin
        require 'aubio'
        backends << :aubio
      rescue LoadError
        # ruby-aubio gem not available
      end
      
      # Check for sonic-annotator
      if system('which sonic-annotator > /dev/null 2>&1')
        backends << :sonic_annotator
      end
      
      backends
    end
  end
end

# Load specific analyzer implementations after base class is defined
require_relative 'aubio_pitch_analyzer'
require_relative 'sonic_annotator_pitch_analyzer'