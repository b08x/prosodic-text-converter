# frozen_string_literal: true

require 'timeout'
require_relative 'logging'
require_relative '../audio/spectrogram'
require_relative '../audio/pitch_analyzer'
require_relative '../analysis/spectrogram_analyzer'
require_relative '../analysis/speech_pattern_extractor'
require_relative '../analysis/prosodic_pattern'
require_relative '../text/text_analyzer'
require_relative '../text/speech_pattern_rewriter'
require_relative '../conversion/llm_converter'
require_relative '../conversion/ssml_formatter'

module ProsodicTextConverter
  # Main application orchestrator for prosodic text conversion
  #
  # @example Basic usage
  #   converter = Converter.new(pattern: :deliberate, provider: :gemini)
  #   result = converter.convert("Hello world")
  #
  # @example With audio analysis
  #   converter = Converter.new(pitch_backend: :aubio)
  #   result = converter.convert_with_audio_analysis("Hello", "voice.wav")
  class Converter
    include Logging

    # @return [ProsodicPattern] current prosodic pattern
    attr_reader :pattern

    # @return [Symbol] current pitch backend
    attr_reader :pitch_backend

    # Initialize a new Converter instance
    #
    # @param pattern [ProsodicPattern, nil] prosodic pattern to use
    # @param provider [Symbol] LLM provider (:gemini, :openai, :anthropic, etc.)
    # @param model [String] model name to use
    # @param pitch_backend [Symbol] pitch analysis backend (:aubio, :sonic_annotator)
    # @param config [Config, nil] configuration object for rephrasing options
    # @param llm_options [Hash] additional options for LLM
    # @raise [ArgumentError] if required dependencies are missing
    # @raise [RuntimeError] if initialization fails
    def initialize(pattern: nil, provider: :gemini, model: 'gemini-2.5-flash', pitch_backend: :aubio,
                   output_dir: './output', config: nil, **llm_options)
      @pitch_backend = pitch_backend
      @output_dir = output_dir
      @config = config

      begin
        logger.info("Initializing Converter with provider: #{provider}, model: #{model}, backend: #{pitch_backend}")

        # Validate pitch backend availability
        validate_pitch_backend(pitch_backend)

        # Initialize components with error handling
        @pattern = pattern || default_pattern
        logger.debug("Using prosodic pattern: #{@pattern.name}")

        @analyzer = initialize_text_analyzer
        @converter = initialize_llm_converter(provider, model, llm_options)
        @formatter = initialize_ssml_formatter
        @spectrogram_generator = initialize_spectrogram_generator
        @spectrogram_analyzer = initialize_spectrogram_analyzer(pitch_backend)
        @speech_pattern_extractor = initialize_speech_pattern_extractor(pitch_backend)
        @speech_pattern_rewriter = initialize_speech_pattern_rewriter(provider, model, llm_options)

        logger.info('Converter initialized successfully')
      rescue StandardError => e
        logger.error("Failed to initialize Converter: #{e.message}")
        logger.debug("Backtrace: #{e.backtrace.join("\n")}")
        raise "Converter initialization failed: #{e.message}"
      end
    end

    # Convert text to SSML using current prosodic pattern
    #
    # @param text [String] text to convert
    # @return [Hash] conversion results with SSML output and analysis
    # @raise [ArgumentError] if text is invalid
    # @raise [RuntimeError] if conversion fails
    def convert(text)
      validate_text_input(text)

      begin
        logger.info("Converting text (#{text.length} chars)")
        start_time = Time.now

        # Analyze text structure with timeout
        text_analysis = Timeout.timeout(30) do
          @analyzer.analyze(text)
        end
        logger.debug("Text analyzed: #{text_analysis[:sentence_count]} sentences")

        # Optional rephrasing step for prosodic optimization
        if @config&.rephrasing_enabled?
          logger.info('Rephrasing enabled, applying SFL-based optimization')
          begin
            rephrasing_options = {
              aggressiveness: @config.rephrasing_aggressiveness,
              meaning_threshold: @config.preserve_meaning_threshold,
              timeout: @config.rephrasing_timeout
            }

            text_analysis = Timeout.timeout(@config.rephrasing_timeout + 10) do
              @converter.rephrase_for_prosody(text_analysis, @pattern, rephrasing_options)
            end
            logger.debug('Text rephrasing completed successfully')
          rescue StandardError => e
            logger.warn("Text rephrasing failed, proceeding with original text: #{e.message}")
            # Continue with original text_analysis if rephrasing fails
          end
        else
          logger.debug('Rephrasing disabled, proceeding with original text')
        end

        # Convert with LLM and timeout (pass rich text analysis and prosodic context)
        ssml_output = Timeout.timeout(120) do
          @converter.convert_text_with_analysis(text_analysis, @pattern)
        end
        logger.debug('LLM conversion completed')

        # Format and validate SSML
        validated_ssml = @formatter.clean_ssml(ssml_output)
        timing_info = @formatter.extract_timing_info(validated_ssml)

        conversion_time = Time.now - start_time
        logger.info("Text conversion completed in #{conversion_time.round(2)}s")

        result = {
          original_text: text,
          ssml_output: validated_ssml,
          pattern_used: @pattern.to_h,
          timing_analysis: timing_info,
          sentences_processed: text_analysis[:sentence_count],
          conversion_time: conversion_time
        }

        # Add rephrasing information if it was applied
        if text_analysis[:rephrasing_applied]
          result[:rephrasing_applied] = true
          result[:original_text_before_rephrasing] = text_analysis[:original_text_before_rephrasing]
          result[:rephrased_text] = text_analysis[:original_text]
          result[:rephrasing_time] = text_analysis[:rephrasing_time]
        else
          result[:rephrasing_applied] = false
        end

        result
      rescue Timeout::Error => e
        error_msg = "Text conversion timed out: #{e.message}"
        logger.error(error_msg)
        raise error_msg.to_s
      rescue StandardError => e
        error_msg = "Text conversion failed: #{e.message}"
        logger.error(error_msg)
        logger.debug("Backtrace: #{e.backtrace.join("\n")}")
        raise error_msg.to_s
      end
    end

    # Extract prosodic pattern from audio file analysis
    #
    # @param audio_file [String] path to audio file
    # @param output_dir [String] directory for spectrogram output
    # @return [Hash] audio analysis results and extracted pattern
    # @raise [ArgumentError] if audio file is invalid
    # @raise [RuntimeError] if analysis fails
    def extract_pattern_from_audio(audio_file, output_dir: nil)
      output_dir ||= @output_dir
      validate_audio_file(audio_file)
      validate_output_directory(output_dir)

      begin
        logger.info("Extracting prosodic pattern from audio: #{audio_file}")
        start_time = Time.now

        # Generate spectrogram with timeout
        spectrogram_result = Timeout.timeout(60) do
          @spectrogram_generator.generate(audio_file, output_dir: output_dir)
        end
        logger.debug("Spectrogram generated: #{spectrogram_result[:spectrogram_file]}")

        # Analyze spectrogram for prosodic patterns with timeout
        analysis_result = Timeout.timeout(120) do
          @spectrogram_analyzer.analyze(spectrogram_result[:spectrogram_file], audio_file: audio_file)
        end
        logger.debug('Audio analysis completed')

        # Update pattern
        @pattern = analysis_result[:recommended_pattern]
        logger.info("Pattern updated from audio analysis: #{@pattern.name}")

        analysis_time = Time.now - start_time
        logger.info("Audio analysis completed in #{analysis_time.round(2)}s")

        # Save pitch data to output directory
        pitch_data_files = save_pitch_data(analysis_result, output_dir, audio_file)
        logger.debug("Pitch data saved to: #{pitch_data_files.values.join(', ')}")

        {
          audio_file: audio_file,
          spectrogram_file: spectrogram_result[:spectrogram_file],
          analysis: analysis_result,
          extracted_pattern: @pattern.to_h,
          pitch_backend_used: @pitch_backend,
          analysis_time: analysis_time,
          pitch_data_files: pitch_data_files
        }
      rescue Timeout::Error => e
        error_msg = "Audio analysis timed out: #{e.message}"
        logger.error(error_msg)
        raise error_msg.to_s
      rescue StandardError => e
        error_msg = "Audio analysis failed: #{e.message}"
        logger.error(error_msg)
        logger.debug("Backtrace: #{e.backtrace.join("\n")}")
        raise error_msg.to_s
      end
    end

    # Convert text using prosodic pattern extracted from audio
    #
    # @param text [String] text to convert
    # @param audio_file [String] path to audio file for pattern extraction
    # @return [Hash] combined audio analysis and text conversion results
    # @raise [ArgumentError] if inputs are invalid
    # @raise [RuntimeError] if conversion fails
    def convert_with_audio_analysis(text, audio_file)
      validate_text_input(text)
      validate_audio_file(audio_file)

      begin
        logger.info('Converting text with audio analysis')
        start_time = Time.now

        # First extract pattern from audio
        pattern_result = extract_pattern_from_audio(audio_file)
        logger.debug('Audio pattern extracted successfully')

        # Then convert text using extracted pattern
        conversion_result = convert(text)
        logger.debug('Text conversion with extracted pattern completed')

        total_time = Time.now - start_time
        logger.info("Audio-guided conversion completed in #{total_time.round(2)}s")

        {
          **conversion_result,
          audio_analysis: pattern_result,
          pattern_source: 'extracted_from_audio',
          total_processing_time: total_time
        }
      rescue StandardError => e
        error_msg = "Audio-guided conversion failed: #{e.message}"
        logger.error(error_msg)
        logger.debug("Backtrace: #{e.backtrace.join("\n")}")
        raise error_msg.to_s
      end
    end

    # Get available pitch analysis backends
    #
    # @return [Array<Symbol>] list of available backends
    def self.available_pitch_backends
      PitchAnalyzerFactory.available_backends
    end

    # Get predefined prosodic patterns
    #
    # @return [Hash<Symbol, ProsodicPattern>] predefined patterns
    def self.predefined_patterns
      {
        deliberate: ProsodicPattern.new(
          name: 'deliberate',
          segment_duration: 1.0,
          pause_duration: 0.35,
          pitch_variation: 5,
          rate: 'medium'
        ),
        rapid: ProsodicPattern.new(
          name: 'rapid',
          segment_duration: 0.6,
          pause_duration: 0.2,
          pitch_variation: 3,
          rate: 'fast'
        ),
        contemplative: ProsodicPattern.new(
          name: 'contemplative',
          segment_duration: 1.4,
          pause_duration: 0.5,
          pitch_variation: 7,
          rate: 'slow'
        ),
        prose: ProsodicPattern.new(
          name: 'prose',
          segment_duration: 6.0,
          pause_duration: 0.15,
          pitch_variation: 3,
          rate: 'medium'
        ),
        natural: ProsodicPattern.new(
          name: 'natural',
          segment_duration: 4.5,
          pause_duration: 0.2,
          pitch_variation: 4,
          rate: 'medium'
        )
      }
    end

    # Convert text using speech patterns extracted from spectrogram
    #
    # @param text [String] text to convert
    # @param spectrogram_file [String] path to spectrogram file for pattern extraction
    # @param options [Hash] conversion options
    # @option options [Boolean] :enable_rewriting enable pattern-based text rewriting
    # @option options [String] :rewrite_strategy rewriting strategy ('rhythm', 'stress', 'intonation', 'hybrid')
    # @option options [Boolean] :preserve_meaning strict meaning preservation
    # @return [Hash] comprehensive conversion results with pattern analysis and rewriting
    # @raise [ArgumentError] if inputs are invalid
    # @raise [RuntimeError] if conversion fails
    def convert_with_spectrogram_patterns(text, spectrogram_file, options = {})
      validate_text_input(text)

      raise ArgumentError, "Spectrogram file not found: #{spectrogram_file}" unless File.exist?(spectrogram_file)

      conversion_options = {
        enable_rewriting: true,
        rewrite_strategy: 'hybrid',
        preserve_meaning: true,
        meaning_threshold: 0.85
      }.merge(options)

      begin
        logger.info('Converting text with spectrogram pattern analysis')
        start_time = Time.now

        # Step 1: Extract speech patterns from spectrogram
        logger.debug('Extracting speech patterns from spectrogram')
        speech_patterns = @speech_pattern_extractor.extract_speech_patterns(spectrogram_file)

        # Step 2: Analyze input text
        logger.debug('Analyzing input text structure')
        text_analysis = @analyzer.analyze(text)

        # Step 3: Generate rewriting guidance from patterns
        logger.debug('Generating rewriting guidance from speech patterns')
        rewrite_guidance = @speech_pattern_extractor.generate_rewrite_guidance(text_analysis)

        result = {}

        # Step 4: Apply pattern-based text rewriting if enabled
        if conversion_options[:enable_rewriting]
          logger.debug('Applying pattern-based text rewriting')

          rewrite_options = {
            strategy: conversion_options[:rewrite_strategy],
            preserve_meaning: conversion_options[:preserve_meaning],
            meaning_threshold: conversion_options[:meaning_threshold]
          }

          rewrite_result = @speech_pattern_rewriter.rewrite_text(
            text_analysis,
            rewrite_guidance,
            rewrite_options
          )

          # Use rewritten text for SSML conversion if rewriting was successful
          if rewrite_result[:rewrite_applied]
            text_analysis = rewrite_result[:rewritten_analysis]
            result[:rewrite_result] = rewrite_result
            logger.info('Text rewriting applied successfully')
          else
            logger.warn('Text rewriting was not applied, using original text')
            result[:rewrite_result] = rewrite_result
          end
        else
          logger.debug('Text rewriting disabled, using original text')
        end

        # Step 5: Extract prosodic pattern from speech analysis
        if speech_patterns[:temporal_patterns] && speech_patterns[:frequency_patterns]
          extracted_pattern = create_pattern_from_speech_analysis(speech_patterns)
          @pattern = extracted_pattern
          logger.debug("Updated prosodic pattern from speech analysis: #{@pattern.name}")
        end

        # Step 6: Convert to SSML using analyzed patterns
        logger.debug('Converting to SSML with extracted patterns')
        ssml_output = @converter.convert_text_with_analysis(text_analysis, @pattern)

        # Step 7: Format and validate SSML
        validated_ssml = @formatter.clean_ssml(ssml_output)
        timing_info = @formatter.extract_timing_info(validated_ssml)

        total_time = Time.now - start_time
        logger.info("Spectrogram-guided conversion completed in #{total_time.round(2)}s")

        # Compile comprehensive results
        result.merge({
                       original_text: text,
                       final_text: text_analysis[:original_text], # May be rewritten text
                       ssml_output: validated_ssml,
                       speech_patterns: speech_patterns,
                       rewrite_guidance: rewrite_guidance,
                       pattern_used: @pattern.to_h,
                       timing_analysis: timing_info,
                       sentences_processed: text_analysis[:sentence_count],
                       total_processing_time: total_time,
                       spectrogram_file: spectrogram_file,
                       pattern_source: 'extracted_from_spectrogram',
                       rewriting_enabled: conversion_options[:enable_rewriting]
                     })
      rescue StandardError => e
        error_msg = "Spectrogram-guided conversion failed: #{e.message}"
        logger.error(error_msg)
        logger.debug("Backtrace: #{e.backtrace.join("\n")}")
        raise error_msg
      end
    end

    # Convert text using speech patterns extracted from audio with intelligent rewriting
    #
    # @param text [String] text to convert
    # @param audio_file [String] path to audio file for pattern extraction
    # @param options [Hash] conversion options
    # @option options [Boolean] :enable_rewriting enable pattern-based text rewriting
    # @option options [String] :rewrite_strategy rewriting strategy
    # @option options [Boolean] :preserve_meaning strict meaning preservation
    # @return [Hash] comprehensive conversion results
    # @raise [ArgumentError] if inputs are invalid
    # @raise [RuntimeError] if conversion fails
    def convert_with_intelligent_rewriting(text, audio_file, options = {})
      validate_text_input(text)
      validate_audio_file(audio_file)

      conversion_options = {
        enable_rewriting: true,
        rewrite_strategy: 'comprehensive',
        preserve_meaning: true,
        meaning_threshold: 0.85
      }.merge(options)

      begin
        logger.info('Converting text with intelligent speech pattern rewriting')
        start_time = Time.now

        # Step 1: Generate spectrogram from audio
        logger.debug('Generating spectrogram from audio')
        spectrogram_result = @spectrogram_generator.generate(audio_file, output_dir: @output_dir)

        # Step 2: Use spectrogram-based conversion with rewriting
        result = convert_with_spectrogram_patterns(
          text,
          spectrogram_result[:spectrogram_file],
          conversion_options
        )

        # Step 3: Enhance result with audio analysis metadata
        result[:audio_file] = audio_file
        result[:spectrogram_generation] = spectrogram_result
        result[:audio_analysis_backend] = @pitch_backend

        total_time = Time.now - start_time
        result[:total_processing_time] = total_time

        logger.info("Intelligent rewriting conversion completed in #{total_time.round(2)}s")
        result
      rescue StandardError => e
        error_msg = "Intelligent rewriting conversion failed: #{e.message}"
        logger.error(error_msg)
        logger.debug("Backtrace: #{e.backtrace.join("\n")}")
        raise error_msg
      end
    end

    # Extract and analyze speech patterns from spectrogram without text conversion
    #
    # @param spectrogram_file [String] path to spectrogram file
    # @param audio_file [String, nil] path to original audio file (optional)
    # @return [Hash] comprehensive speech pattern analysis
    # @raise [ArgumentError] if spectrogram file is invalid
    # @raise [RuntimeError] if analysis fails
    def analyze_speech_patterns(spectrogram_file, audio_file: nil)
      raise ArgumentError, "Spectrogram file not found: #{spectrogram_file}" unless File.exist?(spectrogram_file)

      begin
        logger.info('Analyzing speech patterns from spectrogram')
        start_time = Time.now

        # Extract comprehensive speech patterns
        speech_patterns = @speech_pattern_extractor.extract_speech_patterns(
          spectrogram_file,
          audio_file: audio_file
        )

        analysis_time = Time.now - start_time
        logger.info("Speech pattern analysis completed in #{analysis_time.round(2)}s")

        {
          speech_patterns: speech_patterns,
          spectrogram_file: spectrogram_file,
          audio_file: audio_file,
          analysis_time: analysis_time,
          backend_used: @pitch_backend
        }
      rescue StandardError => e
        error_msg = "Speech pattern analysis failed: #{e.message}"
        logger.error(error_msg)
        logger.debug("Backtrace: #{e.backtrace.join("\n")}")
        raise error_msg
      end
    end

    # Generate rewriting guidance for text based on speech patterns
    #
    # @param text [String] text to analyze for rewriting
    # @param speech_patterns [Hash] extracted speech patterns
    # @return [Hash] comprehensive rewriting guidance
    # @raise [ArgumentError] if inputs are invalid
    # @raise [RuntimeError] if guidance generation fails
    def generate_rewriting_guidance(text, speech_patterns)
      validate_text_input(text)

      unless speech_patterns.is_a?(Hash) && speech_patterns[:temporal_patterns]
        raise ArgumentError, 'Speech patterns must contain temporal_patterns'
      end

      begin
        logger.info('Generating rewriting guidance from speech patterns')
        start_time = Time.now

        # Analyze text structure
        text_analysis = @analyzer.analyze(text)

        # Set up pattern extractor with speech patterns
        @speech_pattern_extractor.instance_variable_set(:@extracted_patterns, speech_patterns)

        # Generate comprehensive guidance
        guidance = @speech_pattern_extractor.generate_rewrite_guidance(text_analysis)

        guidance_time = Time.now - start_time
        logger.info("Rewriting guidance generated in #{guidance_time.round(2)}s")

        {
          text_analysis: text_analysis,
          rewrite_guidance: guidance,
          speech_patterns_used: speech_patterns[:extraction_metadata] || {},
          generation_time: guidance_time
        }
      rescue StandardError => e
        error_msg = "Rewriting guidance generation failed: #{e.message}"
        logger.error(error_msg)
        logger.debug("Backtrace: #{e.backtrace.join("\n")}")
        raise error_msg
      end
    end

    private

    # Get default prosodic pattern
    #
    # @return [ProsodicPattern] default pattern
    def default_pattern
      self.class.predefined_patterns[:prose]
    end

    # Validate pitch backend availability
    #
    # @param backend [Symbol] backend to validate
    # @raise [ArgumentError] if backend is unavailable
    def validate_pitch_backend(backend)
      available = self.class.available_pitch_backends
      return unless available.empty? || !available.include?(backend)

      error_msg = if available.empty?
                    'No pitch analysis backends available'
                  else
                    "Pitch backend '#{backend}' not available. Available: #{available.join(', ')}"
                  end
      logger.error(error_msg)
      raise ArgumentError, error_msg
    end

    # Validate text input
    #
    # @param text [String] text to validate
    # @raise [ArgumentError] if text is invalid
    def validate_text_input(text)
      if text.nil? || text.strip.empty?
        error_msg = 'Text input cannot be nil or empty'
        logger.error(error_msg)
        raise ArgumentError, error_msg
      end

      return unless text.length > 50_000 # Reasonable limit

      error_msg = "Text input too long (#{text.length} chars, max 50000)"
      logger.error(error_msg)
      raise ArgumentError, error_msg
    end

    # Validate audio file input
    #
    # @param audio_file [String] path to audio file
    # @raise [ArgumentError] if audio file is invalid
    def validate_audio_file(audio_file)
      if audio_file.nil? || audio_file.strip.empty?
        error_msg = 'Audio file path cannot be nil or empty'
        logger.error(error_msg)
        raise ArgumentError, error_msg
      end

      unless File.exist?(audio_file)
        error_msg = "Audio file not found: #{audio_file}"
        logger.error(error_msg)
        raise ArgumentError, error_msg
      end

      return if File.readable?(audio_file)

      error_msg = "Audio file not readable: #{audio_file}"
      logger.error(error_msg)
      raise ArgumentError, error_msg
    end

    # Validate output directory
    #
    # @param output_dir [String] directory path
    # @raise [ArgumentError] if directory is invalid
    def validate_output_directory(output_dir)
      begin
        FileUtils.mkdir_p(output_dir) unless Dir.exist?(output_dir)
      rescue StandardError => e
        error_msg = "Cannot create output directory #{output_dir}: #{e.message}"
        logger.error(error_msg)
        raise ArgumentError, error_msg
      end

      return if File.writable?(output_dir)

      error_msg = "Output directory not writable: #{output_dir}"
      logger.error(error_msg)
      raise ArgumentError, error_msg
    end

    # Initialize text analyzer with error handling
    #
    # @return [TextAnalyzer] configured analyzer
    def initialize_text_analyzer
      TextAnalyzer.new(language: :en)
    rescue StandardError => e
      logger.error("Failed to initialize text analyzer: #{e.message}")
      raise "Text analyzer initialization failed: #{e.message}"
    end

    # Initialize LLM converter with error handling
    #
    # @param provider [Symbol] LLM provider
    # @param model [String] model name
    # @param options [Hash] additional options
    # @return [LLMConverter] configured converter
    def initialize_llm_converter(provider, model, options)
      LLMConverter.new(provider: provider, model: model, config: @config, **options)
    rescue StandardError => e
      logger.error("Failed to initialize LLM converter: #{e.message}")
      raise "LLM converter initialization failed: #{e.message}"
    end

    # Initialize SSML formatter with error handling
    #
    # @return [SSMLFormatter] configured formatter
    def initialize_ssml_formatter
      SSMLFormatter.new
    rescue StandardError => e
      logger.error("Failed to initialize SSML formatter: #{e.message}")
      raise "SSML formatter initialization failed: #{e.message}"
    end

    # Initialize spectrogram generator with error handling
    #
    # @return [SpectrogramGenerator] configured generator
    def initialize_spectrogram_generator
      SpectrogramGenerator.new
    rescue StandardError => e
      logger.error("Failed to initialize spectrogram generator: #{e.message}")
      raise "Spectrogram generator initialization failed: #{e.message}"
    end

    # Initialize spectrogram analyzer with error handling
    #
    # @param pitch_backend [Symbol] pitch backend to use
    # @return [SpectrogramAnalyzer] configured analyzer
    def initialize_spectrogram_analyzer(pitch_backend)
      SpectrogramAnalyzer.new(pitch_backend: pitch_backend)
    rescue StandardError => e
      logger.error("Failed to initialize spectrogram analyzer: #{e.message}")
      raise "Spectrogram analyzer initialization failed: #{e.message}"
    end

    # Initialize speech pattern extractor with error handling
    #
    # @param pitch_backend [Symbol] pitch backend to use
    # @return [SpeechPatternExtractor] configured extractor
    def initialize_speech_pattern_extractor(pitch_backend)
      SpeechPatternExtractor.new(pitch_backend: pitch_backend)
    rescue StandardError => e
      logger.error("Failed to initialize speech pattern extractor: #{e.message}")
      raise "Speech pattern extractor initialization failed: #{e.message}"
    end

    # Initialize speech pattern rewriter with error handling
    #
    # @param provider [Symbol] LLM provider
    # @param model [String] model name
    # @param options [Hash] additional options
    # @return [SpeechPatternRewriter] configured rewriter
    def initialize_speech_pattern_rewriter(provider, model, options)
      SpeechPatternRewriter.new(provider: provider, model: model, config: @config, **options)
    rescue StandardError => e
      logger.error("Failed to initialize speech pattern rewriter: #{e.message}")
      raise "Speech pattern rewriter initialization failed: #{e.message}"
    end

    # Create prosodic pattern from speech analysis results
    #
    # @param speech_patterns [Hash] comprehensive speech pattern analysis
    # @return [ProsodicPattern] prosodic pattern derived from speech analysis
    def create_pattern_from_speech_analysis(speech_patterns)
      temporal = speech_patterns[:temporal_patterns]
      rhythm = speech_patterns[:rhythm_patterns]

      # Extract timing parameters
      segment_duration = temporal[:timing_metrics][:average_duration] || 1.0

      # Calculate pause duration from transitions
      pause_duration = if temporal[:transitions] && !temporal[:transitions].empty?
                         temporal[:transitions].map { |t| t[:duration] }.sum / temporal[:transitions].length
                       else
                         0.35
                       end

      # Extract pitch variation (simplified)
      pitch_variation = if speech_patterns[:frequency_patterns][:pitch_contour]
                          5 # Default moderate variation
                        else
                          5
                        end

      # Determine speaking rate from rhythm analysis
      rate = if rhythm && rhythm[:average_tempo]
               tempo = rhythm[:average_tempo]
               case tempo
               when 0..100 then 'slow'
               when 100..140 then 'medium'
               else 'fast'
               end
             else
               'medium'
             end

      # Create pattern name based on characteristics
      pattern_name = "extracted_#{rhythm[:rhythm_regularity] || 'regular'}_#{rate}"

      ProsodicPattern.new(
        name: pattern_name,
        segment_duration: segment_duration.clamp(0.5, 2.5),
        pause_duration: pause_duration.clamp(0.1, 1.0),
        pitch_variation: pitch_variation.clamp(2, 15),
        rate: rate
      )
    end

    # Save pitch data to output directory in multiple formats
    #
    # @param analysis_result [Hash] analysis results containing pitch data
    # @param output_dir [String] output directory path
    # @param audio_file [String] original audio file path for naming
    # @return [Hash] paths to saved data files
    def save_pitch_data(analysis_result, output_dir, audio_file)
      require 'json'
      require 'csv'
      require 'fileutils'

      FileUtils.mkdir_p(output_dir)

      base_name = File.basename(audio_file, '.*')
      timestamp = Time.now.strftime('%Y%m%d_%H%M%S')

      # Prepare pitch data for saving
      pitch_data = analysis_result[:pitch_analysis] || []
      prosodic_features = analysis_result[:prosodic_features] || {}

      # Save as JSON
      json_file = File.join(output_dir, "#{base_name}_pitch_data_#{timestamp}.json")
      json_data = {
        audio_file: audio_file,
        backend: @pitch_backend,
        timestamp: Time.now.iso8601,
        prosodic_features: prosodic_features,
        pitch_data: pitch_data
      }

      File.write(json_file, JSON.pretty_generate(json_data))

      # Save as CSV
      csv_file = File.join(output_dir, "#{base_name}_pitch_data_#{timestamp}.csv")
      CSV.open(csv_file, 'w') do |csv|
        csv << %w[timestamp frequency_hz confidence] # Header
        pitch_data.each do |point|
          csv << [point[:timestamp], point[:frequency], point[:confidence] || 1.0]
        end
      end

      {
        json: json_file,
        csv: csv_file
      }
    rescue StandardError => e
      logger.warn("Failed to save pitch data: #{e.message}")
      {}
    end
  end
end
