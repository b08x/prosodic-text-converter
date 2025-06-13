# frozen_string_literal: true

require 'mini_magick'
require_relative '../core/logging'
require_relative '../audio/pitch_analyzer'
require_relative 'prosodic_pattern'

module ProsodicTextConverter
  # Advanced speech pattern extraction from spectrograms for text rewriting
  #
  # This class analyzes spectrograms to extract detailed speech patterns including
  # rhythm, intonation, stress patterns, and emotional markers that can be used
  # to intelligently rewrite text for better prosodic matching.
  #
  # @example Basic usage
  #   extractor = SpeechPatternExtractor.new(pitch_backend: :aubio)
  #   patterns = extractor.extract_speech_patterns('voice_spectrogram.png')
  #   rewrite_guidance = extractor.generate_rewrite_guidance(patterns, text_analysis)
  class SpeechPatternExtractor
    include Logging

    # @return [Hash] detailed speech patterns extracted from audio
    attr_reader :extracted_patterns

    # Initialize speech pattern extractor
    #
    # @param pitch_backend [Symbol] pitch analysis backend (:aubio or :sonic_annotator)
    # @param options [Hash] analysis options
    # @option options [Boolean] :detailed_analysis enable detailed pattern analysis
    # @option options [Boolean] :emotional_detection enable emotional pattern detection
    # @option options [Float] :rhythm_sensitivity sensitivity for rhythm detection (0.1-1.0)
    # @raise [RuntimeError] if dependencies are missing
    def initialize(pitch_backend: :aubio, options: {})
      @pitch_analyzer = PitchAnalyzerFactory.create(backend: pitch_backend)
      @pitch_backend = pitch_backend
      @options = default_options.merge(options)
      @extracted_patterns = {}
      validate_dependencies
    end

    # Extract comprehensive speech patterns from spectrogram
    #
    # @param spectrogram_file [String] path to spectrogram image file
    # @param audio_file [String, nil] path to original audio file (optional)
    # @return [Hash] comprehensive speech pattern analysis
    # @raise [RuntimeError] if spectrogram file not found
    def extract_speech_patterns(spectrogram_file, audio_file: nil)
      raise "Spectrogram file not found: #{spectrogram_file}" unless File.exist?(spectrogram_file)

      logger.info("Extracting speech patterns from spectrogram: #{File.basename(spectrogram_file)}")
      start_time = Time.now

      # Get the original audio file path
      audio_file = audio_file || derive_audio_file_path(spectrogram_file)

      image = MiniMagick::Image.open(spectrogram_file)

      # Extract multi-dimensional speech patterns
      temporal_patterns = extract_temporal_patterns(image)
      frequency_patterns = extract_frequency_patterns(image, audio_file)
      rhythm_patterns = extract_rhythm_patterns(image, temporal_patterns)
      stress_patterns = extract_stress_patterns(image, frequency_patterns)
      intonation_patterns = extract_intonation_patterns(image, audio_file)
      
      # Advanced pattern analysis if enabled
      emotional_patterns = @options[:emotional_detection] ? extract_emotional_patterns(image, audio_file) : {}
      breathing_patterns = extract_breathing_patterns(image, temporal_patterns)
      
      extraction_time = Time.now - start_time
      logger.info("Speech pattern extraction completed in #{extraction_time.round(2)}s")

      @extracted_patterns = {
        temporal_patterns: temporal_patterns,
        frequency_patterns: frequency_patterns,
        rhythm_patterns: rhythm_patterns,
        stress_patterns: stress_patterns,
        intonation_patterns: intonation_patterns,
        emotional_patterns: emotional_patterns,
        breathing_patterns: breathing_patterns,
        extraction_metadata: {
          spectrogram_file: spectrogram_file,
          audio_file: audio_file,
          backend_used: @pitch_backend,
          extraction_time: extraction_time,
          detailed_analysis: @options[:detailed_analysis]
        }
      }
    end

    # Generate text rewriting guidance based on extracted speech patterns
    #
    # @param text_analysis [Hash] structured text analysis from TextAnalyzer
    # @return [Hash] comprehensive rewriting guidance
    def generate_rewrite_guidance(text_analysis)
      raise 'No speech patterns extracted. Call extract_speech_patterns first.' if @extracted_patterns.empty?

      logger.info("Generating text rewriting guidance for #{text_analysis[:sentence_count]} sentences")

      guidance = {
        overall_strategy: determine_overall_rewrite_strategy,
        sentence_guidance: generate_sentence_guidance(text_analysis[:sentences]),
        rhythm_adjustments: generate_rhythm_adjustments(text_analysis),
        stress_adjustments: generate_stress_adjustments(text_analysis),
        intonation_guidance: generate_intonation_guidance(text_analysis),
        pacing_recommendations: generate_pacing_recommendations(text_analysis),
        emotional_alignment: generate_emotional_alignment(text_analysis),
        prosodic_targets: generate_prosodic_targets
      }

      logger.debug("Generated rewriting guidance with #{guidance[:sentence_guidance].length} sentence-level recommendations")
      guidance
    end

    private

    # Default analysis options
    #
    # @return [Hash] default options
    def default_options
      {
        detailed_analysis: true,
        emotional_detection: true,
        rhythm_sensitivity: 0.7,
        stress_detection_threshold: 0.6,
        intonation_smoothing: 0.3
      }
    end

    # Validate required dependencies
    #
    # @raise [RuntimeError] if dependencies are missing
    def validate_dependencies
      require 'mini_magick'
    rescue LoadError
      raise 'MiniMagick gem required for spectrogram analysis. Run: gem install mini_magick'
    end

    # Derive original audio file path from spectrogram filename
    #
    # @param spectrogram_file [String] path to spectrogram file
    # @return [String, nil] path to audio file or nil if not found
    def derive_audio_file_path(spectrogram_file)
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

      nil
    end

    # Extract temporal patterns from spectrogram
    #
    # @param image [MiniMagick::Image] spectrogram image
    # @return [Hash] temporal pattern analysis
    def extract_temporal_patterns(image)
      width = image.width
      height = image.height

      # Convert to grayscale for analysis
      grayscale = image.dup.colorspace('Gray')

      # Extract energy profile across time
      energy_profile = extract_detailed_energy_profile(grayscale, width, height)
      
      # Detect speech segments with enhanced segmentation
      segments = detect_enhanced_speech_segments(energy_profile)
      
      # Analyze segment transitions
      transitions = analyze_segment_transitions(segments)
      
      # Calculate timing metrics
      timing_metrics = calculate_timing_metrics(segments)

      {
        total_duration: estimate_duration_from_width(width),
        segments: segments,
        transitions: transitions,
        timing_metrics: timing_metrics,
        energy_profile: energy_profile,
        speech_to_silence_ratio: calculate_speech_to_silence_ratio(segments),
        segment_regularity: assess_segment_regularity(segments)
      }
    end

    # Extract frequency patterns from spectrogram and audio
    #
    # @param image [MiniMagick::Image] spectrogram image
    # @param audio_file [String, nil] path to audio file
    # @return [Hash] frequency pattern analysis
    def extract_frequency_patterns(image, audio_file)
      height = image.height

      # Define frequency regions
      fundamental_region = (height * 0.1).to_i..(height * 0.3).to_i
      harmonic_region = (height * 0.3).to_i..(height * 0.7).to_i
      upper_region = (height * 0.7).to_i..(height * 0.9).to_i

      # Get pitch analysis from audio if available
      pitch_analysis = analyze_pitch_from_audio(audio_file)

      # Extract frequency patterns
      patterns = {
        fundamental_patterns: analyze_frequency_region(image, fundamental_region),
        harmonic_patterns: analyze_frequency_region(image, harmonic_region),
        upper_frequency_patterns: analyze_frequency_region(image, upper_region),
        pitch_contour: extract_pitch_contour(pitch_analysis),
        formant_patterns: extract_formant_patterns(image, height),
        spectral_centroid: calculate_spectral_centroid(image)
      }

      # Enhanced metrics for sonic-annotator
      if @pitch_backend == :sonic_annotator && pitch_analysis && !pitch_analysis.empty?
        patterns[:advanced_pitch_metrics] = extract_advanced_pitch_metrics(pitch_analysis)
      end

      patterns
    end

    # Extract rhythm patterns from temporal analysis
    #
    # @param image [MiniMagick::Image] spectrogram image
    # @param temporal_patterns [Hash] temporal pattern data
    # @return [Hash] rhythm pattern analysis
    def extract_rhythm_patterns(image, temporal_patterns)
      segments = temporal_patterns[:segments]
      
      # Calculate inter-onset intervals
      onset_intervals = calculate_onset_intervals(segments)
      
      # Detect rhythmic regularity
      rhythm_regularity = assess_rhythm_regularity(onset_intervals)
      
      # Identify rhythmic groupings
      rhythmic_groups = identify_rhythmic_groups(segments)
      
      # Calculate tempo variations
      tempo_variations = calculate_tempo_variations(onset_intervals)

      {
        onset_intervals: onset_intervals,
        rhythm_regularity: rhythm_regularity,
        rhythmic_groups: rhythmic_groups,
        tempo_variations: tempo_variations,
        average_tempo: calculate_average_tempo(onset_intervals),
        rhythm_complexity: assess_rhythm_complexity(onset_intervals),
        syncopation_index: calculate_syncopation_index(onset_intervals)
      }
    end

    # Extract stress patterns from frequency analysis
    #
    # @param image [MiniMagick::Image] spectrogram image
    # @param frequency_patterns [Hash] frequency pattern data
    # @return [Hash] stress pattern analysis
    def extract_stress_patterns(image, frequency_patterns)
      # Identify stressed syllables based on energy and pitch
      stress_markers = identify_stress_markers(frequency_patterns)
      
      # Analyze stress timing
      stress_timing = analyze_stress_timing(stress_markers)
      
      # Calculate stress regularity
      stress_regularity = assess_stress_regularity(stress_markers)

      {
        stress_markers: stress_markers,
        stress_timing: stress_timing,
        stress_regularity: stress_regularity,
        primary_stress_pattern: identify_primary_stress_pattern(stress_markers),
        secondary_stress_pattern: identify_secondary_stress_pattern(stress_markers),
        stress_density: calculate_stress_density(stress_markers)
      }
    end

    # Extract intonation patterns from pitch analysis
    #
    # @param image [MiniMagick::Image] spectrogram image
    # @param audio_file [String, nil] path to audio file
    # @return [Hash] intonation pattern analysis
    def extract_intonation_patterns(image, audio_file)
      pitch_analysis = analyze_pitch_from_audio(audio_file)
      return { available: false } unless pitch_analysis && !pitch_analysis.empty?

      # Extract pitch contours
      pitch_contours = extract_pitch_contours(pitch_analysis)
      
      # Identify intonation phrases
      intonation_phrases = identify_intonation_phrases(pitch_contours)
      
      # Analyze pitch movements
      pitch_movements = analyze_pitch_movements(pitch_contours)
      
      # Calculate intonation metrics
      intonation_metrics = calculate_intonation_metrics(pitch_contours)

      {
        available: true,
        pitch_contours: pitch_contours,
        intonation_phrases: intonation_phrases,
        pitch_movements: pitch_movements,
        intonation_metrics: intonation_metrics,
        overall_contour_shape: classify_overall_contour_shape(pitch_contours),
        boundary_tones: extract_boundary_tones(pitch_contours)
      }
    end

    # Extract emotional patterns from spectrogram and audio
    #
    # @param image [MiniMagick::Image] spectrogram image
    # @param audio_file [String, nil] path to audio file
    # @return [Hash] emotional pattern analysis
    def extract_emotional_patterns(image, audio_file)
      return { available: false } unless @options[:emotional_detection]

      # Extract emotional indicators from spectral features
      spectral_emotions = extract_spectral_emotional_markers(image)
      
      # Extract emotional indicators from prosodic features
      prosodic_emotions = extract_prosodic_emotional_markers(audio_file)
      
      # Combine and classify emotional state
      emotional_state = classify_emotional_state(spectral_emotions, prosodic_emotions)

      {
        available: true,
        spectral_emotions: spectral_emotions,
        prosodic_emotions: prosodic_emotions,
        emotional_state: emotional_state,
        arousal_level: calculate_arousal_level(spectral_emotions),
        valence_level: calculate_valence_level(prosodic_emotions),
        emotional_consistency: assess_emotional_consistency(emotional_state)
      }
    end

    # Extract breathing patterns from temporal analysis
    #
    # @param image [MiniMagick::Image] spectrogram image
    # @param temporal_patterns [Hash] temporal pattern data
    # @return [Hash] breathing pattern analysis
    def extract_breathing_patterns(image, temporal_patterns)
      segments = temporal_patterns[:segments]
      
      # Identify potential breath pauses
      breath_pauses = identify_breath_pauses(segments)
      
      # Analyze breathing rhythm
      breathing_rhythm = analyze_breathing_rhythm(breath_pauses)
      
      # Calculate breathing metrics
      breathing_metrics = calculate_breathing_metrics(breath_pauses, segments)

      {
        breath_pauses: breath_pauses,
        breathing_rhythm: breathing_rhythm,
        breathing_metrics: breathing_metrics,
        breath_group_size: calculate_average_breath_group_size(segments, breath_pauses),
        breathing_regularity: assess_breathing_regularity(breath_pauses)
      }
    end

    # Analyze pitch data from original audio file
    #
    # @param audio_file [String, nil] path to audio file
    # @return [Array<Hash>, nil] pitch analysis data or nil if unavailable
    def analyze_pitch_from_audio(audio_file)
      return nil unless audio_file && File.exist?(audio_file)

      begin
        @pitch_analyzer.analyze(audio_file)
      rescue StandardError => e
        logger.warn("Pitch analysis failed (#{e.message}), using spectrogram-only analysis")
        nil
      end
    end

    # Generate overall rewriting strategy based on patterns
    #
    # @return [Hash] overall strategy recommendations
    def determine_overall_rewrite_strategy
      patterns = @extracted_patterns

      strategy = {
        primary_focus: determine_primary_focus(patterns),
        rewrite_aggressiveness: determine_rewrite_aggressiveness(patterns),
        rhythm_priority: assess_rhythm_priority(patterns),
        stress_priority: assess_stress_priority(patterns),
        intonation_priority: assess_intonation_priority(patterns)
      }

      # Add emotional consideration if available
      if patterns[:emotional_patterns][:available]
        strategy[:emotional_alignment] = assess_emotional_alignment_priority(patterns)
      end

      strategy
    end

    # Generate sentence-level rewriting guidance
    #
    # @param sentences [Array<Hash>] sentence analysis data
    # @return [Array<Hash>] guidance for each sentence
    def generate_sentence_guidance(sentences)
      patterns = @extracted_patterns
      guidance = []

      sentences.each_with_index do |sentence, index|
        sentence_guidance = {
          sentence_index: index,
          original_text: sentence[:text],
          recommended_changes: generate_sentence_changes(sentence, patterns),
          target_timing: calculate_target_sentence_timing(sentence, patterns),
          stress_recommendations: generate_sentence_stress_recommendations(sentence, patterns),
          pause_recommendations: generate_sentence_pause_recommendations(sentence, patterns)
        }

        guidance << sentence_guidance
      end

      guidance
    end

    # Placeholder methods for detailed pattern analysis
    # These would contain sophisticated signal processing algorithms

    def extract_detailed_energy_profile(image, width, height)
      # Simplified implementation - would use actual pixel analysis
      energy_profile = []
      (0...width).step(width / 200).each do |x|
        total_energy = 0
        sample_count = 0
        (height * 0.2).to_i.upto((height * 0.8).to_i) do |y|
          total_energy += 128 # Placeholder energy value
          sample_count += 1
        end
        energy_profile << total_energy / sample_count.to_f
      end
      energy_profile
    end

    def detect_enhanced_speech_segments(energy_profile)
      threshold = energy_profile.sum / energy_profile.length * 0.6
      segments = []
      current_segment = nil

      energy_profile.each_with_index do |energy, index|
        time = index * 0.01

        if energy > threshold
          if current_segment.nil?
            current_segment = { start: time, end: time, energy_peak: energy }
          else
            current_segment[:end] = time
            current_segment[:energy_peak] = [current_segment[:energy_peak], energy].max
          end
        elsif current_segment
          current_segment[:duration] = current_segment[:end] - current_segment[:start]
          segments << current_segment if current_segment[:duration] > 0.05
          current_segment = nil
        end
      end

      if current_segment
        current_segment[:duration] = current_segment[:end] - current_segment[:start]
        segments << current_segment if current_segment[:duration] > 0.05
      end

      segments
    end

    def analyze_segment_transitions(segments)
      transitions = []
      segments.each_cons(2) do |seg1, seg2|
        transition_duration = seg2[:start] - seg1[:end]
        transition_type = classify_transition_type(transition_duration, seg1, seg2)
        
        transitions << {
          from_segment: seg1,
          to_segment: seg2,
          duration: transition_duration,
          type: transition_type
        }
      end
      transitions
    end

    def calculate_timing_metrics(segments)
      return {} if segments.empty?

      durations = segments.map { |s| s[:duration] }
      
      {
        average_duration: durations.sum / durations.length,
        duration_variance: calculate_variance(durations),
        min_duration: durations.min,
        max_duration: durations.max,
        total_speech_time: durations.sum
      }
    end

    def calculate_speech_to_silence_ratio(segments)
      return 0 if segments.empty?

      total_speech = segments.sum { |s| s[:duration] }
      total_duration = segments.last[:end] - segments.first[:start]
      total_silence = total_duration - total_speech
      
      total_silence > 0 ? total_speech / total_silence : Float::INFINITY
    end

    def assess_segment_regularity(segments)
      return 'regular' if segments.length < 3

      durations = segments.map { |s| s[:duration] }
      variance = calculate_variance(durations)

      case variance
      when 0..0.05 then 'very_regular'
      when 0.05..0.15 then 'regular'
      when 0.15..0.3 then 'somewhat_irregular'
      else 'irregular'
      end
    end

    def classify_transition_type(duration, seg1, seg2)
      case duration
      when 0..0.1 then 'connected'
      when 0.1..0.3 then 'short_pause'
      when 0.3..0.7 then 'medium_pause'
      else 'long_pause'
      end
    end

    def estimate_duration_from_width(width)
      # Assuming ~200 pixels per second (from spectrogram generation default)
      width / 200.0
    end

    def calculate_variance(values)
      return 0 if values.empty?

      mean = values.sum / values.length.to_f
      variance = values.map { |v| (v - mean)**2 }.sum / values.length.to_f
      Math.sqrt(variance)
    end

    # Placeholder implementations for complex analysis methods
    # In a production system, these would contain sophisticated algorithms

    def analyze_frequency_region(image, region)
      { average_energy: 128, peak_frequency: region.first + (region.size / 2) }
    end

    def extract_pitch_contour(pitch_analysis)
      return [] unless pitch_analysis
      pitch_analysis.map { |p| { time: p[:timestamp], frequency: p[:frequency] } }
    end

    def extract_formant_patterns(image, height)
      { f1: height * 0.2, f2: height * 0.4, f3: height * 0.6 }
    end

    def calculate_spectral_centroid(image)
      image.height * 0.4 # Placeholder calculation
    end

    def extract_advanced_pitch_metrics(pitch_analysis)
      frequencies = pitch_analysis.map { |p| p[:frequency] }.reject(&:zero?)
      return {} if frequencies.length < 10

      {
        pitch_range_hz: frequencies.max - frequencies.min,
        pitch_stability: calculate_pitch_stability(pitch_analysis),
        jitter: calculate_jitter(frequencies),
        shimmer: calculate_shimmer(frequencies)
      }
    end

    def calculate_pitch_stability(pitch_analysis)
      frequencies = pitch_analysis.map { |p| p[:frequency] }
      differences = frequencies.each_cons(2).map { |a, b| (b - a).abs }
      mean_freq = frequencies.sum / frequencies.length.to_f
      mean_diff = differences.sum / differences.length.to_f
      1.0 - [mean_diff / mean_freq, 1.0].min
    end

    def calculate_jitter(frequencies)
      return 0 if frequencies.length < 3
      period_differences = frequencies.each_cons(2).map { |a, b| (b - a).abs }
      mean_period = frequencies.sum / frequencies.length.to_f
      mean_diff = period_differences.sum / period_differences.length.to_f
      mean_diff / mean_period
    end

    def calculate_shimmer(frequencies)
      # Simplified shimmer calculation
      calculate_jitter(frequencies) * 0.8
    end

    # Additional placeholder methods for comprehensive analysis
    def calculate_onset_intervals(segments)
      segments.each_cons(2).map { |s1, s2| s2[:start] - s1[:start] }
    end

    def assess_rhythm_regularity(intervals)
      return 'regular' if intervals.length < 2
      variance = calculate_variance(intervals)
      case variance
      when 0..0.05 then 'very_regular'
      when 0.05..0.1 then 'regular'
      else 'irregular'
      end
    end

    def identify_rhythmic_groups(segments)
      # Group segments by similar timing patterns
      segments.each_slice(3).to_a
    end

    def calculate_tempo_variations(intervals)
      return [] if intervals.length < 2
      intervals.each_cons(2).map { |i1, i2| (i2 - i1).abs }
    end

    def calculate_average_tempo(intervals)
      return 0 if intervals.empty?
      60.0 / (intervals.sum / intervals.length)
    end

    def assess_rhythm_complexity(intervals)
      variance = calculate_variance(intervals)
      case variance
      when 0..0.1 then 'simple'
      when 0.1..0.3 then 'moderate'
      else 'complex'
      end
    end

    def calculate_syncopation_index(intervals)
      # Simplified syncopation calculation
      variance = calculate_variance(intervals)
      [variance * 10, 1.0].min
    end

    def identify_stress_markers(frequency_patterns)
      # Simplified stress identification
      [{ time: 0.5, strength: 0.8 }, { time: 1.2, strength: 0.6 }]
    end

    def analyze_stress_timing(stress_markers)
      intervals = stress_markers.each_cons(2).map { |s1, s2| s2[:time] - s1[:time] }
      { average_interval: intervals.sum / intervals.length, regularity: assess_rhythm_regularity(intervals) }
    end

    def assess_stress_regularity(stress_markers)
      'regular' # Placeholder
    end

    def identify_primary_stress_pattern(stress_markers)
      'iambic' # Placeholder
    end

    def identify_secondary_stress_pattern(stress_markers)
      'weak' # Placeholder
    end

    def calculate_stress_density(stress_markers)
      stress_markers.length / 10.0 # Placeholder: stresses per 10 seconds
    end

    # Continue with remaining placeholder methods...
    def extract_pitch_contours(pitch_analysis)
      pitch_analysis.map { |p| { time: p[:timestamp], frequency: p[:frequency] } }
    end

    def identify_intonation_phrases(pitch_contours)
      # Group contours into phrases based on pitch reset points
      [pitch_contours] # Simplified
    end

    def analyze_pitch_movements(pitch_contours)
      movements = []
      pitch_contours.each_cons(2) do |p1, p2|
        direction = p2[:frequency] > p1[:frequency] ? 'rising' : 'falling'
        magnitude = (p2[:frequency] - p1[:frequency]).abs
        movements << { direction: direction, magnitude: magnitude }
      end
      movements
    end

    def calculate_intonation_metrics(pitch_contours)
      frequencies = pitch_contours.map { |p| p[:frequency] }
      {
        range: frequencies.max - frequencies.min,
        average: frequencies.sum / frequencies.length,
        slope: calculate_overall_slope(pitch_contours)
      }
    end

    def classify_overall_contour_shape(pitch_contours)
      return 'flat' if pitch_contours.empty?
      
      first_freq = pitch_contours.first[:frequency]
      last_freq = pitch_contours.last[:frequency]
      
      if last_freq > first_freq * 1.1
        'rising'
      elsif last_freq < first_freq * 0.9
        'falling'
      else
        'flat'
      end
    end

    def extract_boundary_tones(pitch_contours)
      return {} if pitch_contours.empty?
      
      {
        initial: pitch_contours.first[:frequency],
        final: pitch_contours.last[:frequency]
      }
    end

    def calculate_overall_slope(pitch_contours)
      return 0 if pitch_contours.length < 2
      
      first = pitch_contours.first
      last = pitch_contours.last
      time_diff = last[:time] - first[:time]
      freq_diff = last[:frequency] - first[:frequency]
      
      time_diff > 0 ? freq_diff / time_diff : 0
    end

    # Emotional analysis placeholder methods
    def extract_spectral_emotional_markers(image)
      { brightness: 0.6, roughness: 0.3, spectral_flux: 0.4 }
    end

    def extract_prosodic_emotional_markers(audio_file)
      { tempo_variation: 0.5, pitch_variation: 0.7, intensity_variation: 0.4 }
    end

    def classify_emotional_state(spectral, prosodic)
      'neutral' # Placeholder - would use ML models in production
    end

    def calculate_arousal_level(spectral_emotions)
      spectral_emotions[:spectral_flux] || 0.5
    end

    def calculate_valence_level(prosodic_emotions)
      prosodic_emotions[:pitch_variation] || 0.5
    end

    def assess_emotional_consistency(emotional_state)
      'consistent' # Placeholder
    end

    # Breathing analysis placeholder methods
    def identify_breath_pauses(segments)
      # Identify longer pauses that likely indicate breathing
      pauses = []
      segments.each_cons(2) do |seg1, seg2|
        pause_duration = seg2[:start] - seg1[:end]
        if pause_duration > 0.4 # Threshold for breath pause
          pauses << { start: seg1[:end], duration: pause_duration, type: 'breath' }
        end
      end
      pauses
    end

    def analyze_breathing_rhythm(breath_pauses)
      return {} if breath_pauses.length < 2
      
      intervals = breath_pauses.each_cons(2).map { |p1, p2| p2[:start] - p1[:start] }
      {
        average_interval: intervals.sum / intervals.length,
        regularity: assess_rhythm_regularity(intervals)
      }
    end

    def calculate_breathing_metrics(breath_pauses, segments)
      total_speech_time = segments.sum { |s| s[:duration] }
      total_breath_time = breath_pauses.sum { |p| p[:duration] }
      
      {
        breath_to_speech_ratio: total_breath_time / total_speech_time,
        average_breath_duration: breath_pauses.sum { |p| p[:duration] } / breath_pauses.length,
        breath_frequency: breath_pauses.length / total_speech_time
      }
    end

    def calculate_average_breath_group_size(segments, breath_pauses)
      return segments.length if breath_pauses.empty?
      segments.length.to_f / (breath_pauses.length + 1)
    end

    def assess_breathing_regularity(breath_pauses)
      return 'regular' if breath_pauses.length < 2
      
      durations = breath_pauses.map { |p| p[:duration] }
      variance = calculate_variance(durations)
      
      case variance
      when 0..0.1 then 'very_regular'
      when 0.1..0.2 then 'regular'
      else 'irregular'
      end
    end

    # Strategy determination methods
    def determine_primary_focus(patterns)
      # Determine what aspect needs most attention
      rhythm_score = assess_pattern_complexity(patterns[:rhythm_patterns])
      stress_score = assess_pattern_complexity(patterns[:stress_patterns])
      intonation_score = assess_pattern_complexity(patterns[:intonation_patterns])
      
      scores = { rhythm: rhythm_score, stress: stress_score, intonation: intonation_score }
      scores.max_by { |_, score| score }.first
    end

    def determine_rewrite_aggressiveness(patterns)
      complexity_score = assess_overall_complexity(patterns)
      case complexity_score
      when 0..0.3 then 'conservative'
      when 0.3..0.7 then 'moderate'
      else 'aggressive'
      end
    end

    def assess_rhythm_priority(patterns)
      patterns[:rhythm_patterns][:rhythm_complexity] == 'complex' ? 'high' : 'medium'
    end

    def assess_stress_priority(patterns)
      patterns[:stress_patterns][:stress_regularity] == 'irregular' ? 'high' : 'medium'
    end

    def assess_intonation_priority(patterns)
      patterns[:intonation_patterns][:available] ? 'high' : 'low'
    end

    def assess_emotional_alignment_priority(patterns)
      emotional_state = patterns[:emotional_patterns][:emotional_state]
      emotional_state == 'neutral' ? 'low' : 'high'
    end

    def assess_pattern_complexity(pattern_data)
      # Return a complexity score between 0 and 1
      0.5 # Placeholder
    end

    def assess_overall_complexity(patterns)
      # Calculate overall complexity across all patterns
      0.6 # Placeholder
    end

    # Sentence guidance generation methods
    def generate_sentence_changes(sentence, patterns)
      changes = []
      
      # Analyze sentence length against rhythm patterns
      if sentence[:word_count] > patterns[:rhythm_patterns][:average_tempo] * 2
        changes << {
          type: 'length_reduction',
          reason: 'sentence_too_long_for_rhythm',
          suggestion: 'Consider breaking into shorter clauses'
        }
      end
      
      # Check stress patterns
      if patterns[:stress_patterns][:stress_density] > 0.8
        changes << {
          type: 'stress_adjustment',
          reason: 'high_stress_density',
          suggestion: 'Reduce stressed syllables through word choice'
        }
      end
      
      changes
    end

    def calculate_target_sentence_timing(sentence, patterns)
      base_duration = sentence[:word_count] * 0.3 # ~300ms per word
      rhythm_factor = patterns[:rhythm_patterns][:average_tempo] / 120.0 # Normalize to 120 BPM
      
      {
        target_duration: base_duration * rhythm_factor,
        recommended_pauses: calculate_recommended_pauses(sentence, patterns),
        timing_flexibility: assess_timing_flexibility(sentence, patterns)
      }
    end

    def generate_sentence_stress_recommendations(sentence, patterns)
      stress_pattern = patterns[:stress_patterns][:primary_stress_pattern]
      
      {
        pattern_to_match: stress_pattern,
        recommended_stress_words: identify_stress_candidates(sentence),
        stress_timing: calculate_stress_timing(sentence, patterns)
      }
    end

    def generate_sentence_pause_recommendations(sentence, patterns)
      pause_indicators = sentence[:pause_indicators]
      breathing_patterns = patterns[:breathing_patterns]
      
      recommendations = []
      
      # Add breathing pauses if needed
      if breathing_patterns[:breath_frequency] > 0.3
        recommendations << {
          type: 'breath_pause',
          duration: breathing_patterns[:average_breath_duration] || 0.5,
          placement: 'after_clause'
        }
      end
      
      # Add rhythm-based pauses
      if patterns[:rhythm_patterns][:rhythm_regularity] == 'regular'
        recommendations << {
          type: 'rhythm_pause',
          duration: 0.2,
          placement: 'phrase_boundary'
        }
      end
      
      recommendations
    end

    # Additional helper methods
    def calculate_recommended_pauses(sentence, patterns)
      pause_indicators = sentence[:pause_indicators] || []
      base_pauses = pause_indicators.length
      rhythm_pauses = patterns[:rhythm_patterns][:rhythmic_groups].length - 1
      
      [base_pauses, rhythm_pauses].max
    end

    def assess_timing_flexibility(sentence, patterns)
      word_count = sentence[:word_count]
      rhythm_regularity = patterns[:rhythm_patterns][:rhythm_regularity]
      
      case rhythm_regularity
      when 'very_regular' then word_count < 8 ? 'low' : 'medium'
      when 'regular' then 'medium'
      else 'high'
      end
    end

    def identify_stress_candidates(sentence)
      words = sentence[:words] || []
      # Prefer longer words and content words for stress
      words.select { |w| w[:syllable_count] > 1 }.map { |w| w[:text] }
    end

    def calculate_stress_timing(sentence, patterns)
      stress_interval = patterns[:stress_patterns][:stress_timing][:average_interval] || 1.0
      sentence_duration = sentence[:word_count] * 0.3
      
      {
        expected_stresses: (sentence_duration / stress_interval).round,
        stress_interval: stress_interval
      }
    end

    # Comprehensive guidance generation methods
    def generate_rhythm_adjustments(text_analysis)
      patterns = @extracted_patterns[:rhythm_patterns]
      
      {
        target_tempo: patterns[:average_tempo],
        rhythm_type: patterns[:rhythm_regularity],
        adjustments: determine_rhythm_adjustments(text_analysis, patterns)
      }
    end

    def generate_stress_adjustments(text_analysis)
      patterns = @extracted_patterns[:stress_patterns]
      
      {
        stress_pattern: patterns[:primary_stress_pattern],
        stress_density: patterns[:stress_density],
        adjustments: determine_stress_adjustments(text_analysis, patterns)
      }
    end

    def generate_intonation_guidance(text_analysis)
      patterns = @extracted_patterns[:intonation_patterns]
      
      if patterns[:available]
        {
          available: true,
          contour_shape: patterns[:overall_contour_shape],
          boundary_tones: patterns[:boundary_tones],
          guidance: determine_intonation_guidance(text_analysis, patterns)
        }
      else
        { available: false }
      end
    end

    def generate_pacing_recommendations(text_analysis)
      temporal_patterns = @extracted_patterns[:temporal_patterns]
      
      {
        overall_pace: determine_overall_pace(temporal_patterns),
        segment_pacing: determine_segment_pacing(text_analysis, temporal_patterns),
        pause_strategy: determine_pause_strategy(temporal_patterns)
      }
    end

    def generate_emotional_alignment(text_analysis)
      emotional_patterns = @extracted_patterns[:emotional_patterns]
      
      if emotional_patterns[:available]
        {
          available: true,
          target_emotion: emotional_patterns[:emotional_state],
          arousal_target: emotional_patterns[:arousal_level],
          valence_target: emotional_patterns[:valence_level],
          alignment_strategy: determine_emotional_alignment_strategy(text_analysis, emotional_patterns)
        }
      else
        { available: false }
      end
    end

    def generate_prosodic_targets
      patterns = @extracted_patterns
      
      {
        rhythm_target: extract_rhythm_target(patterns[:rhythm_patterns]),
        stress_target: extract_stress_target(patterns[:stress_patterns]),
        intonation_target: extract_intonation_target(patterns[:intonation_patterns]),
        timing_target: extract_timing_target(patterns[:temporal_patterns])
      }
    end

    # Final helper methods for guidance generation
    def determine_rhythm_adjustments(text_analysis, patterns)
      []  # Placeholder - would contain specific rhythm modification suggestions
    end

    def determine_stress_adjustments(text_analysis, patterns)
      []  # Placeholder - would contain specific stress modification suggestions
    end

    def determine_intonation_guidance(text_analysis, patterns)
      []  # Placeholder - would contain specific intonation suggestions
    end

    def determine_overall_pace(temporal_patterns)
      avg_duration = temporal_patterns[:timing_metrics][:average_duration] || 1.0
      case avg_duration
      when 0..0.8 then 'fast'
      when 0.8..1.2 then 'medium'
      else 'slow'
      end
    end

    def determine_segment_pacing(text_analysis, temporal_patterns)
      # Map sentences to timing segments
      text_analysis[:sentences].map.with_index do |sentence, index|
        {
          sentence_index: index,
          recommended_pace: determine_sentence_pace(sentence, temporal_patterns)
        }
      end
    end

    def determine_sentence_pace(sentence, temporal_patterns)
      word_count = sentence[:word_count]
      avg_segment_duration = temporal_patterns[:timing_metrics][:average_duration] || 1.0
      
      target_duration = word_count * 0.3
      if target_duration > avg_segment_duration * 1.2
        'slow_down'
      elsif target_duration < avg_segment_duration * 0.8
        'speed_up'
      else
        'maintain'
      end
    end

    def determine_pause_strategy(temporal_patterns)
      speech_to_silence = temporal_patterns[:speech_to_silence_ratio]
      
      case speech_to_silence
      when 0..2 then 'increase_pauses'
      when 2..4 then 'maintain_pauses'
      else 'reduce_pauses'
      end
    end

    def determine_emotional_alignment_strategy(text_analysis, emotional_patterns)
      target_emotion = emotional_patterns[:emotional_state]
      
      {
        emotion: target_emotion,
        strategies: generate_emotion_strategies(target_emotion),
        text_modifications: suggest_emotional_text_modifications(text_analysis, target_emotion)
      }
    end

    def generate_emotion_strategies(emotion)
      case emotion
      when 'neutral' then ['maintain_steady_pace', 'use_moderate_stress']
      when 'excited' then ['increase_tempo', 'add_stress_variation', 'use_rising_intonation']
      when 'calm' then ['slower_pace', 'regular_breathing_pauses', 'falling_intonation']
      else ['match_prosodic_features']
      end
    end

    def suggest_emotional_text_modifications(text_analysis, emotion)
      # Placeholder for emotion-specific text modifications
      []
    end

    # Target extraction methods
    def extract_rhythm_target(rhythm_patterns)
      {
        tempo: rhythm_patterns[:average_tempo],
        regularity: rhythm_patterns[:rhythm_regularity],
        complexity: rhythm_patterns[:rhythm_complexity]
      }
    end

    def extract_stress_target(stress_patterns)
      {
        pattern: stress_patterns[:primary_stress_pattern],
        density: stress_patterns[:stress_density],
        regularity: stress_patterns[:stress_regularity]
      }
    end

    def extract_intonation_target(intonation_patterns)
      if intonation_patterns[:available]
        {
          available: true,
          contour_shape: intonation_patterns[:overall_contour_shape],
          pitch_range: intonation_patterns[:intonation_metrics][:range],
          boundary_tones: intonation_patterns[:boundary_tones]
        }
      else
        { available: false }
      end
    end

    def extract_timing_target(temporal_patterns)
      {
        segment_duration: temporal_patterns[:timing_metrics][:average_duration],
        segment_regularity: temporal_patterns[:segment_regularity],
        speech_to_silence_ratio: temporal_patterns[:speech_to_silence_ratio]
      }
    end
  end
end