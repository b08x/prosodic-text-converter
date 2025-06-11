# frozen_string_literal: true

require_relative '../audio/spectrogram'
require_relative '../audio/pitch_analyzer'
require_relative '../analysis/spectrogram_analyzer'
require_relative '../analysis/prosodic_pattern'
require_relative '../text/text_analyzer'
require_relative '../conversion/llm_converter'
require_relative '../conversion/ssml_formatter'

module ProsodicTextConverter
  # Main application orchestrator
  class Converter
    def initialize(pattern: nil, provider: :openai, model: 'gpt-4', pitch_backend: :aubio, **llm_options)
      @pattern = pattern || default_pattern
      @analyzer = TextAnalyzer.new(@pattern)
      @converter = LLMConverter.new(
        provider: provider, 
        model: model, 
        **llm_options
      )
      @formatter = SSMLFormatter.new
      @spectrogram_generator = SpectrogramGenerator.new
      @spectrogram_analyzer = SpectrogramAnalyzer.new(pitch_backend: pitch_backend)
      @pitch_backend = pitch_backend
    end

    def convert(text)
      chunks = @analyzer.chunk_text(text)
      ssml_output = @converter.convert_text(text, @pattern, chunks)
      
      validated_ssml = @formatter.clean_ssml(ssml_output)
      timing_info = @formatter.extract_timing_info(validated_ssml)
      
      {
        original_text: text,
        ssml_output: validated_ssml,
        pattern_used: @pattern.to_h,
        timing_analysis: timing_info,
        chunks_processed: chunks.length
      }
    end

    def extract_pattern_from_audio(audio_file, output_dir: './spectrograms')
      # Generate spectrogram
      spectrogram_result = @spectrogram_generator.generate(audio_file, output_dir: output_dir)
      
      # Analyze spectrogram for prosodic patterns (now with real pitch analysis)
      analysis_result = @spectrogram_analyzer.analyze(spectrogram_result[:spectrogram_file])
      
      # Update our pattern
      @pattern = analysis_result[:recommended_pattern]
      @analyzer = TextAnalyzer.new(@pattern)
      
      {
        audio_file: audio_file,
        spectrogram_file: spectrogram_result[:spectrogram_file],
        analysis: analysis_result,
        extracted_pattern: @pattern.to_h,
        pitch_backend_used: @pitch_backend
      }
    end

    def convert_with_audio_analysis(text, audio_file)
      # First extract pattern from audio
      pattern_result = extract_pattern_from_audio(audio_file)
      
      # Then convert text using extracted pattern
      conversion_result = convert(text)
      
      {
        **conversion_result,
        audio_analysis: pattern_result,
        pattern_source: 'extracted_from_audio'
      }
    end

    def self.available_pitch_backends
      PitchAnalyzerFactory.available_backends
    end

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

    def default_pattern
      self.class.predefined_patterns[:deliberate]
    end
  end
end