# frozen_string_literal: true

require 'timeout'
require_relative 'logging'
require_relative '../audio/spectrogram'
require_relative '../audio/pitch_analyzer'
require_relative '../analysis/spectrogram_analyzer'
require_relative '../analysis/prosodic_pattern'
require_relative '../text/text_analyzer'
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
    # @param llm_options [Hash] additional options for LLM
    # @raise [ArgumentError] if required dependencies are missing
    # @raise [RuntimeError] if initialization fails
    def initialize(pattern: nil, provider: :gemini, model: 'gemini-2.0-flash', pitch_backend: :aubio,
                   output_dir: './output', **llm_options)
      @pitch_backend = pitch_backend
      @output_dir = output_dir

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

        {
          original_text: text,
          ssml_output: validated_ssml,
          pattern_used: @pattern.to_h,
          timing_analysis: timing_info,
          sentences_processed: text_analysis[:sentence_count],
          conversion_time: conversion_time
        }
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
        )
      }
    end

    private

    # Get default prosodic pattern
    #
    # @return [ProsodicPattern] default pattern
    def default_pattern
      self.class.predefined_patterns[:deliberate]
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
      LLMConverter.new(provider: provider, model: model, **options)
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
        csv << ['timestamp', 'frequency_hz', 'confidence'] # Header
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
