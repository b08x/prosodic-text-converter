# frozen_string_literal: true

require 'mini_magick'
require_relative '../core/logging'
require_relative '../audio/pitch_analyzer'
require_relative 'prosodic_pattern'

module ProsodicTextConverter
  # Custom exception for analysis failures
  class AnalysisError < StandardError; end

  # Enhanced spectrogram analysis with comprehensive pitch backends
  #
  # @example Basic usage
  #   analyzer = SpectrogramAnalyzer.new(pitch_backend: :aubio)
  #   analysis = analyzer.analyze('voice_spectrogram.png')
  class SpectrogramAnalyzer
    include Logging
    # Initialize spectrogram analyzer with pitch backend
    #
    # @param pitch_backend [Symbol] pitch analysis backend (:aubio or :sonic_annotator)
    # @raise [RuntimeError] if dependencies are missing
    def initialize(pitch_backend: :aubio)
      @pitch_analyzer = PitchAnalyzerFactory.create(backend: pitch_backend)
      @pitch_backend = pitch_backend
      validate_dependencies
    end

    # Analyze spectrogram file to extract prosodic patterns
    #
    # @param spectrogram_file [String] path to spectrogram image file
    # @return [Hash] comprehensive analysis results with prosodic features
    # @raise [RuntimeError] if spectrogram file not found
    def analyze(spectrogram_file)
      raise "Spectrogram file not found: #{spectrogram_file}" unless File.exist?(spectrogram_file)

      # Get the original audio file path from spectrogram filename
      audio_file = derive_audio_file_path(spectrogram_file)

      image = MiniMagick::Image.open(spectrogram_file)

      # Extract basic image properties
      width = image.width
      height = image.height

      # Analyze temporal structure from spectrogram
      temporal_analysis = analyze_temporal_structure(image)

      # Get comprehensive pitch analysis from audio (if available)
      pitch_analysis = analyze_pitch_from_audio(audio_file)

      # Combine spectrogram and pitch analysis
      frequency_analysis = analyze_frequency_patterns(image, pitch_analysis)

      # Extract prosodic features with backend-specific enhancements
      prosodic_features = extract_prosodic_features(temporal_analysis, frequency_analysis, pitch_analysis)

      {
        image_properties: { width: width, height: height },
        temporal_analysis: temporal_analysis,
        frequency_analysis: frequency_analysis,
        pitch_analysis: pitch_analysis,
        prosodic_features: prosodic_features,
        recommended_pattern: create_prosodic_pattern(prosodic_features),
        analysis_backend: @pitch_backend
      }
    end

    private

    # Validate required dependencies for image analysis
    #
    # @raise [RuntimeError] if MiniMagick gem is not available
    def validate_dependencies
      require 'mini_magick'
    rescue LoadError
      raise 'MiniMagick gem required for image analysis. Run: gem install mini_magick'
    end

    # Derive original audio file path from spectrogram filename
    #
    # @param spectrogram_file [String] path to spectrogram file
    # @return [String, nil] path to audio file or nil if not found
    def derive_audio_file_path(spectrogram_file)
      # Try to find the original audio file based on spectrogram filename
      base_name = File.basename(spectrogram_file, '_spectrogram.png')
      dir = File.dirname(spectrogram_file)

      # Look for common audio extensions
      %w[.wav .mp3 .flac .m4a .aiff .ogg].each do |ext|
        audio_path = File.join(dir, "#{base_name}#{ext}")
        return audio_path if File.exist?(audio_path)
      end

      # Try parent directory
      parent_dir = File.dirname(dir)
      %w[.wav .mp3 .flac .m4a .aiff .ogg].each do |ext|
        audio_path = File.join(parent_dir, "#{base_name}#{ext}")
        return audio_path if File.exist?(audio_path)
      end

      nil # Audio file not found
    end

    # Analyze pitch data from original audio file if available
    #
    # @param audio_file [String, nil] path to audio file
    # @return [Array<Hash>, nil] pitch analysis data or nil if unavailable
    def analyze_pitch_from_audio(audio_file)
      return nil unless audio_file && File.exist?(audio_file)

      begin
        @pitch_analyzer.analyze(audio_file)
      rescue StandardError => e
        # If pitch analysis fails, continue with spectrogram-only analysis
        puts "Warning: Pitch analysis failed (#{e.message}), using spectrogram-only analysis"
        nil
      end
    end

    # Analyze temporal structure from spectrogram image
    #
    # @param image [MiniMagick::Image] spectrogram image
    # @return [Hash] temporal analysis with segments and timing
    def analyze_temporal_structure(image)
      # Convert to grayscale and get pixel data for temporal analysis
      grayscale = image.dup.colorspace('Gray')

      # Analyze horizontal patterns to detect speech segments and pauses
      width = grayscale.width
      height = grayscale.height

      # Sample horizontal slices to detect energy patterns
      energy_profile = extract_energy_profile(grayscale, width, height)
      segments = detect_speech_segments(energy_profile)

      {
        total_duration: estimate_duration_from_width(width),
        segments: segments,
        average_segment_duration: segments.any? ? segments.map { |s| s[:duration] }.sum / segments.length : 1.0,
        pause_pattern: analyze_pause_pattern(segments)
      }
    end

    # Analyze frequency patterns combining spectrogram and pitch data
    #
    # @param image [MiniMagick::Image] spectrogram image
    # @param pitch_analysis [Array<Hash>, nil] pitch analysis data
    # @return [Hash] frequency analysis with pitch variation metrics
    def analyze_frequency_patterns(image, pitch_analysis)
      height = image.height

      # Sample frequency bands for pitch analysis
      fundamental_freq_region = (height * 0.1).to_i..(height * 0.3).to_i
      harmonic_region = (height * 0.3).to_i..(height * 0.7).to_i

      # Use real pitch analysis if available, otherwise raise error
      pitch_variation = if pitch_analysis && !pitch_analysis.empty?
                          @pitch_analyzer.calculate_pitch_variation(pitch_analysis)
                        else
                          raise AnalysisError, 'Pitch analysis failed; cannot proceed with spectrogram-only estimation.'
                        end

      # Enhanced analysis for sonic-annotator
      additional_metrics = {}
      if @pitch_backend == :sonic_annotator && pitch_analysis && !pitch_analysis.empty?
        additional_metrics = extract_advanced_pitch_metrics(pitch_analysis)
      end

      {
        fundamental_range: fundamental_freq_region,
        harmonic_range: harmonic_region,
        estimated_pitch_variation: pitch_variation,
        pitch_data_source: pitch_analysis ? 'audio_analysis' : 'spectrogram_estimation',
        backend_used: @pitch_backend,
        **additional_metrics
      }
    end

    def extract_advanced_pitch_metrics(pitch_analysis)
      # Enhanced metrics available from sonic-annotator's comprehensive analysis
      frequencies = pitch_analysis.map { |p| p[:frequency] }.reject(&:zero?)
      return {} if frequencies.length < 10

      # Calculate additional prosodic measures
      {
        pitch_range_semitones: calculate_pitch_range_semitones(frequencies),
        pitch_stability: calculate_pitch_stability(pitch_analysis),
        voiced_segments: count_voiced_segments(pitch_analysis),
        average_pitch_hz: frequencies.sum / frequencies.length.to_f,
        tempo_variability: extract_tempo_variability(pitch_analysis)
      }
    end

    def calculate_pitch_range_semitones(frequencies)
      return 0 if frequencies.empty?

      min_freq = frequencies.min
      max_freq = frequencies.max

      # Convert to semitones: 12 * log2(f2/f1)
      12 * Math.log2(max_freq / min_freq)
    end

    def calculate_pitch_stability(pitch_analysis)
      return 1.0 if pitch_analysis.length < 3

      # Calculate how stable the pitch contour is
      frequencies = pitch_analysis.map { |p| p[:frequency] }
      differences = frequencies.each_cons(2).map { |a, b| (b - a).abs }

      mean_freq = frequencies.sum / frequencies.length.to_f
      mean_diff = differences.sum / differences.length.to_f

      # Stability metric: lower values = more stable
      1.0 - [mean_diff / mean_freq, 1.0].min
    end

    def count_voiced_segments(pitch_analysis)
      # Count continuous voiced segments
      segments = 0
      in_segment = false

      pitch_analysis.each do |point|
        if point[:frequency] > 0
          segments += 1 unless in_segment
          in_segment = true
        else
          in_segment = false
        end
      end

      segments
    end

    def extract_tempo_variability(pitch_analysis)
      # Extract tempo information if available from sonic-annotator
      tempo_points = pitch_analysis.select { |p| p[:tempo_context] }
      return 0.0 if tempo_points.length < 2

      tempos = tempo_points.map { |p| p[:tempo_context] }
      mean_tempo = tempos.sum / tempos.length.to_f
      variance = tempos.map { |t| (t - mean_tempo)**2 }.sum / tempos.length.to_f

      Math.sqrt(variance) / mean_tempo # Coefficient of variation
    end

    def extract_energy_profile(_image, width, height)
      # Simplified energy extraction - sample middle frequencies
      energy_profile = []
      sample_region = (height * 0.2).to_i..(height * 0.8).to_i

      (0...width).step(width / 100).each do |_x|
        total_energy = 0
        sample_count = 0

        sample_region.each do |_y|
          # Get pixel intensity (simplified - would need actual pixel access in real implementation)
          total_energy += 128 # Placeholder - represents average energy
          sample_count += 1
        end

        energy_profile << total_energy / sample_count.to_f
      end

      energy_profile
    end

    def detect_speech_segments(energy_profile)
      # Simple segmentation based on energy thresholds
      threshold = energy_profile.sum / energy_profile.length * 0.7
      segments = []
      current_segment = nil

      energy_profile.each_with_index do |energy, index|
        time = index * 0.01 # Rough time estimation

        if energy > threshold
          if current_segment.nil?
            current_segment = { start: time, end: time }
          else
            current_segment[:end] = time
          end
        elsif current_segment
          current_segment[:duration] = current_segment[:end] - current_segment[:start]
          segments << current_segment if current_segment[:duration] > 0.1
          current_segment = nil
        end
      end

      # Add final segment if exists
      if current_segment
        current_segment[:duration] = current_segment[:end] - current_segment[:start]
        segments << current_segment if current_segment[:duration] > 0.1
      end

      segments
    end

    def analyze_pause_pattern(segments)
      return { average_pause: 0.35 } if segments.length < 2

      pauses = []
      segments.each_cons(2) do |seg1, seg2|
        pause_duration = seg2[:start] - seg1[:end]
        pauses << pause_duration if pause_duration > 0
      end

      {
        average_pause: pauses.any? ? pauses.sum / pauses.length : 0.35,
        pause_count: pauses.length,
        pause_variance: calculate_variance(pauses)
      }
    end

    def estimate_duration_from_width(width)
      # Assuming ~200 pixels per second (from script default)
      width / 200.0
    end

    def calculate_variance(values)
      return 0 if values.empty?

      mean = values.sum / values.length.to_f
      variance = values.map { |v| (v - mean)**2 }.sum / values.length.to_f
      Math.sqrt(variance)
    end

    # Extract comprehensive prosodic features from analysis data
    #
    # @param temporal [Hash] temporal analysis results
    # @param frequency [Hash] frequency analysis results
    # @param pitch_analysis [Array<Hash>, nil] pitch analysis data
    # @return [Hash] prosodic features for pattern creation
    def extract_prosodic_features(temporal, frequency, pitch_analysis)
      base_features = {
        segment_duration: temporal[:average_segment_duration].clamp(0.5, 2.0),
        pause_duration: temporal[:pause_pattern][:average_pause].clamp(0.1, 1.0),
        pitch_variation: frequency[:estimated_pitch_variation].clamp(2, 15),
        speaking_rate: determine_speaking_rate(temporal[:average_segment_duration]),
        rhythm_regularity: assess_rhythm_regularity(temporal[:segments]),
        analysis_method: frequency[:pitch_data_source],
        backend_used: frequency[:backend_used]
      }

      # Add enhanced features from sonic-annotator
      if @pitch_backend == :sonic_annotator && pitch_analysis && !pitch_analysis.empty?
        advanced_features = {
          pitch_range_semitones: frequency[:pitch_range_semitones] || 0,
          pitch_stability: frequency[:pitch_stability] || 1.0,
          voiced_segments: frequency[:voiced_segments] || 0,
          average_pitch_hz: frequency[:average_pitch_hz] || 150.0,
          tempo_variability: frequency[:tempo_variability] || 0.0
        }

        base_features.merge!(advanced_features)
      end

      base_features
    end

    def determine_speaking_rate(avg_segment_duration)
      case avg_segment_duration
      when 0.5..0.7 then 'fast'
      when 0.7..1.2 then 'medium'
      else 'slow'
      end
    end

    def assess_rhythm_regularity(segments)
      return 'regular' if segments.length < 3

      durations = segments.map { |s| s[:duration] }
      variance = calculate_variance(durations)

      case variance
      when 0..0.1 then 'very_regular'
      when 0.1..0.3 then 'regular'
      else 'irregular'
      end
    end

    # Create prosodic pattern from extracted features
    #
    # @param features [Hash] prosodic features
    # @return [ProsodicPattern] configured prosodic pattern
    def create_prosodic_pattern(features)
      ProsodicPattern.new(
        name: "extracted_via_#{features[:analysis_method]}_#{features[:backend_used]}",
        segment_duration: features[:segment_duration],
        pause_duration: features[:pause_duration],
        pitch_variation: features[:pitch_variation],
        rate: features[:speaking_rate]
      )
    end
  end
end
