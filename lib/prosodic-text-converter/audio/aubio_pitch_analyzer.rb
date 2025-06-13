# frozen_string_literal: true


# FFI-based audio analysis
begin
  require 'aubio'
rescue LoadError
  raise LoadError, 'Aubio gem not found. Install with: gem install aubio'
end

module ProsodicTextConverter
  # FFI-based Aubio pitch analysis implementation using YIN algorithm
  #
  # @example Basic usage
  #   analyzer = AubioPitchAnalyzer.new
  #   pitch_data = analyzer.analyze('voice.wav')
  class AubioPitchAnalyzer < PitchAnalyzer
    # @return [String] pitch detection algorithm
    attr_reader :algorithm

    # @return [Integer] hop size for analysis
    attr_reader :hop_size

    # @return [Integer] buffer size for analysis
    attr_reader :buffer_size

    # @return [Integer] sample rate for analysis
    attr_reader :sample_rate

    # Initialize Aubio pitch analyzer with FFI
    #
    # @param algorithm [String] pitch detection algorithm ('yin', 'mcomb', 'fcomb', 'schmitt')
    # @param hop_size [Integer] hop size in samples
    # @param buffer_size [Integer] buffer size in samples
    # @param sample_rate [Integer] sample rate in Hz
    def initialize(algorithm: 'yin', hop_size: 512, buffer_size: 1024, sample_rate: 44_100)
      super()
      @algorithm = algorithm
      @hop_size = hop_size
      @buffer_size = buffer_size
      @sample_rate = sample_rate

      begin
        logger.info("Aubio analyzer initialized (#{@algorithm}, hop: #{@hop_size}, buffer: #{@buffer_size})")
      rescue StandardError => e
        logger.error("Failed to initialize Aubio analyzer: #{e.message}")
        raise
      end
    end

    # Analyze audio file using FFI-based Aubio
    #
    # @param audio_file [String] path to audio file
    # @return [Array<Hash>] pitch analysis data with timestamps and frequencies
    # @raise [ArgumentError] if audio file is invalid
    # @raise [RuntimeError] if analysis fails
    def analyze(audio_file)
      validate_audio_file(audio_file)

      begin
        logger.info("Starting FFI Aubio pitch analysis: #{File.basename(audio_file)}")
        start_time = Time.now

        pitch_data = []

        # Initialize Aubio components via FFI
        source = Aubio::Source.new(audio_file, sample_rate: @sample_rate, hop_size: @hop_size)
        pitch_detector = Aubio::Pitch.new(algorithm: @algorithm, buffer_size: @buffer_size,
                                          hop_size: @hop_size, sample_rate: @sample_rate)

        # Process audio in chunks
        frame_count = 0

        while source.do_multi
          samples = source.get_next_samples
          break if samples.empty?

          # Extract pitch for this frame
          frequency = pitch_detector.do(samples)
          timestamp = frame_count * @hop_size / @sample_rate.to_f

          # Filter out unvoiced segments and unreasonable frequencies
          if frequency >= 50.0 && frequency <= 800.0 # Reasonable speech range
            pitch_data << {
              timestamp: timestamp,
              frequency: frequency
            }
          end

          frame_count += 1
        end

        analysis_time = Time.now - start_time
        logger.info("FFI Aubio analysis completed in #{analysis_time.round(2)}s, #{pitch_data.length} data points")

        if pitch_data.empty?
          logger.warn('No valid pitch data extracted from audio')
        else
          freq_range = pitch_data.map { |p| p[:frequency] }
          logger.debug("Frequency range: #{freq_range.min.round(1)}-#{freq_range.max.round(1)} Hz")
        end

        pitch_data
      rescue StandardError => e
        error_msg = "FFI Aubio analysis failed: #{e.message}"
        logger.error(error_msg)
        logger.debug("Backtrace: #{e.backtrace.join("\n")}")
        raise error_msg.to_s
      end
    end
  end
end
