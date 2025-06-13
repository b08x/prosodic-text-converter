# frozen_string_literal: true

require 'shellwords'

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

        # Convert MP3 to WAV if needed (aubio gem works better with WAV)
        working_file = audio_file
        if File.extname(audio_file).downcase == '.mp3'
          working_file = "/tmp/aubio_#{Process.pid}_#{Time.now.to_i}.wav"
          unless system("sox #{audio_file.shellescape} #{working_file.shellescape}", out: File::NULL, err: File::NULL)
            raise "Failed to convert MP3 to WAV for aubio processing"
          end
        end

        # Initialize Aubio components via correct API
        aubio_params = {
          sample_rate: @sample_rate,
          hop_size: @hop_size,
          window_size: @buffer_size,
          pitch_method: @algorithm == 'yin' ? 'yinfast' : @algorithm,
          confidence_thresh: 0.7
        }
        
        aubio = Aubio.open(working_file, aubio_params)

        # Process audio and extract pitch data
        frame_time = @hop_size / @sample_rate.to_f
        current_time = 0.0

        aubio.pitches.each do |pitch_info|
          frequency = pitch_info[:pitch]
          confidence = pitch_info[:confidence]

          # Convert MIDI note to frequency if needed and filter reasonable speech range
          if frequency > 0 && confidence > aubio_params[:confidence_thresh]
            # If pitch is in MIDI format, convert to Hz
            freq_hz = frequency > 20 ? frequency : 440 * (2**((frequency - 69) / 12.0))
            
            if freq_hz >= 50.0 && freq_hz <= 800.0 # Reasonable speech range
              pitch_data << {
                timestamp: current_time,
                frequency: freq_hz,
                confidence: confidence
              }
            end
          end

          current_time += frame_time
        end

        aubio.close

        # Clean up temporary file if created
        File.unlink(working_file) if working_file != audio_file && File.exist?(working_file)

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
      ensure
        # Clean up temporary file if it was created and still exists
        if defined?(working_file) && working_file != audio_file && File.exist?(working_file)
          File.unlink(working_file) rescue nil
        end
      end
    end
  end
end
