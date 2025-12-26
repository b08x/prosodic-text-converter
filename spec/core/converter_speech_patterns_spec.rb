# frozen_string_literal: true

require 'spec_helper'
require 'prosodic-text-converter/core/converter'

RSpec.describe ProsodicTextConverter::Converter, 'Speech Pattern Integration' do
  let(:test_files_dir) { File.join(__dir__, '..', 'test_files') }
  let(:test_audio) { File.join(test_files_dir, 'test_audio.wav') }
  let(:test_spectrogram) { File.join(test_files_dir, 'test_spectrogram.png') }
  let(:output_dir) { File.join(__dir__, '..', '..', 'tmp', 'test_output') }
  let(:sample_text) { 'Hello world. This is a test sentence for speech pattern analysis.' }

  let(:converter) do
    described_class.new(
      pattern: :deliberate,
      provider: :gemini,
      model: 'gemini-2.5-flash',
      pitch_backend: :aubio,
      output_dir: output_dir
    )
  end

  let(:mock_speech_patterns) do
    {
      temporal_patterns: {
        total_duration: 3.0,
        segments: [
          { start: 0.0, end: 1.0, duration: 1.0, energy_peak: 150 },
          { start: 1.2, end: 2.5, duration: 1.3, energy_peak: 160 }
        ],
        transitions: [
          { from_segment: { end: 1.0 }, to_segment: { start: 1.2 }, duration: 0.2, type: 'short_pause' }
        ],
        timing_metrics: {
          average_duration: 1.15,
          duration_variance: 0.15,
          total_speech_time: 2.3
        },
        speech_to_silence_ratio: 2.5,
        segment_regularity: 'regular'
      },
      frequency_patterns: {
        pitch_contour: [
          { time: 0.0, frequency: 150.0 },
          { time: 1.0, frequency: 155.0 },
          { time: 2.0, frequency: 160.0 }
        ],
        fundamental_patterns: { average_energy: 128, peak_frequency: 200 },
        harmonic_patterns: { average_energy: 95, peak_frequency: 400 },
        spectral_centroid: 300
      },
      rhythm_patterns: {
        onset_intervals: [1.0, 1.2, 1.1],
        rhythm_regularity: 'regular',
        rhythmic_groups: [
          [{ start: 0.0, duration: 1.0 }, { start: 1.2, duration: 1.3 }]
        ],
        tempo_variations: [0.2, 0.1],
        average_tempo: 120,
        rhythm_complexity: 'moderate',
        syncopation_index: 0.3
      },
      stress_patterns: {
        stress_markers: [
          { time: 0.5, strength: 0.8 },
          { time: 1.8, strength: 0.6 }
        ],
        stress_timing: {
          average_interval: 1.3,
          regularity: 'regular'
        },
        stress_regularity: 'regular',
        primary_stress_pattern: 'iambic',
        secondary_stress_pattern: 'weak',
        stress_density: 0.6
      },
      intonation_patterns: {
        available: true,
        pitch_contours: [
          { time: 0.0, frequency: 150.0 },
          { time: 1.0, frequency: 155.0 },
          { time: 2.0, frequency: 160.0 }
        ],
        intonation_phrases: [
          [{ time: 0.0, frequency: 150.0 }, { time: 2.0, frequency: 160.0 }]
        ],
        pitch_movements: [
          { direction: 'rising', magnitude: 5.0 },
          { direction: 'rising', magnitude: 5.0 }
        ],
        intonation_metrics: {
          range: 10.0,
          average: 155.0,
          slope: 5.0
        },
        overall_contour_shape: 'rising',
        boundary_tones: { initial: 150.0, final: 160.0 }
      },
      emotional_patterns: {
        available: true,
        spectral_emotions: { brightness: 0.6, roughness: 0.3, spectral_flux: 0.4 },
        prosodic_emotions: { tempo_variation: 0.5, pitch_variation: 0.7, intensity_variation: 0.4 },
        emotional_state: 'neutral',
        arousal_level: 0.5,
        valence_level: 0.5,
        emotional_consistency: 'consistent'
      },
      breathing_patterns: {
        breath_pauses: [
          { start: 1.0, duration: 0.2, type: 'breath' }
        ],
        breathing_rhythm: {
          average_interval: 3.0,
          regularity: 'regular'
        },
        breathing_metrics: {
          breath_to_speech_ratio: 0.1,
          average_breath_duration: 0.2,
          breath_frequency: 0.33
        },
        breath_group_size: 2.0,
        breathing_regularity: 'regular'
      },
      extraction_metadata: {
        spectrogram_file: test_spectrogram,
        audio_file: test_audio,
        backend_used: :aubio,
        extraction_time: 1.5,
        detailed_analysis: true
      }
    }
  end

  let(:mock_rewrite_guidance) do
    {
      overall_strategy: {
        primary_focus: 'rhythm',
        rewrite_aggressiveness: 'medium',
        rhythm_priority: 'high',
        stress_priority: 'medium',
        intonation_priority: 'low'
      },
      sentence_guidance: [
        {
          sentence_index: 0,
          original_text: 'Hello world.',
          recommended_changes: [],
          target_timing: { target_duration: 1.5, recommended_pauses: 1 }
        }
      ],
      rhythm_adjustments: {
        target_tempo: 120,
        rhythm_type: 'regular'
      },
      stress_adjustments: {
        stress_pattern: 'iambic',
        stress_density: 0.6
      },
      intonation_guidance: {
        available: true,
        contour_shape: 'rising'
      },
      prosodic_targets: {
        rhythm_target: { tempo: 120, regularity: 'regular' },
        stress_target: { pattern: 'iambic', density: 0.6 }
      }
    }
  end

  before do
    # Create test directories
    FileUtils.mkdir_p(test_files_dir) unless Dir.exist?(test_files_dir)
    FileUtils.mkdir_p(output_dir) unless Dir.exist?(output_dir)

    # Create placeholder test files
    File.write(test_audio, 'WAV_PLACEHOLDER') unless File.exist?(test_audio)
    File.write(test_spectrogram, 'PNG_PLACEHOLDER') unless File.exist?(test_spectrogram)

    # Mock external dependencies
    mock_spectrogram_generator
    mock_speech_pattern_extractor
    mock_speech_pattern_rewriter
    mock_llm_converter
    mock_ssml_formatter
  end

  after do
    # Clean up test files
    FileUtils.rm_rf(output_dir) if Dir.exist?(output_dir)
  end

  describe '#convert_with_spectrogram_patterns' do
    it 'successfully converts text using spectrogram patterns' do
      result = converter.convert_with_spectrogram_patterns(sample_text, test_spectrogram)

      expect(result).to be_a(Hash)
      expect(result).to have_key(:original_text)
      expect(result).to have_key(:final_text)
      expect(result).to have_key(:ssml_output)
      expect(result).to have_key(:speech_patterns)
      expect(result).to have_key(:rewrite_guidance)
      expect(result).to have_key(:pattern_used)
      expect(result).to have_key(:timing_analysis)
      expect(result).to have_key(:total_processing_time)
      expect(result).to have_key(:spectrogram_file)
      expect(result).to have_key(:pattern_source)
      expect(result).to have_key(:rewriting_enabled)

      expect(result[:original_text]).to eq(sample_text)
      expect(result[:pattern_source]).to eq('extracted_from_spectrogram')
      expect(result[:rewriting_enabled]).to be(true)
    end

    it 'applies text rewriting when enabled' do
      options = { enable_rewriting: true, rewrite_strategy: 'rhythm' }

      result = converter.convert_with_spectrogram_patterns(sample_text, test_spectrogram, options)

      expect(result).to have_key(:rewrite_result)
      expect(result[:rewrite_result][:rewrite_applied]).to be(true)
      expect(result[:rewrite_result][:strategy_used]).to eq('rhythm')
    end

    it 'skips rewriting when disabled' do
      options = { enable_rewriting: false }

      result = converter.convert_with_spectrogram_patterns(sample_text, test_spectrogram, options)

      expect(result[:rewriting_enabled]).to be(false)
      expect(result).not_to have_key(:rewrite_result)
    end

    it 'updates prosodic pattern from speech analysis' do
      original_pattern_name = converter.pattern.name

      result = converter.convert_with_spectrogram_patterns(sample_text, test_spectrogram)

      # Pattern should be updated from speech analysis
      expect(converter.pattern.name).not_to eq(original_pattern_name)
      expect(converter.pattern.name).to include('extracted')
      expect(result[:pattern_used][:name]).to include('extracted')
    end

    it 'handles different rewrite strategies' do
      strategies = %w[rhythm stress intonation hybrid comprehensive]

      strategies.each do |strategy|
        options = { enable_rewriting: true, rewrite_strategy: strategy }
        result = converter.convert_with_spectrogram_patterns(sample_text, test_spectrogram, options)

        expect(result[:rewrite_result][:strategy_used]).to eq(strategy)
      end
    end

    it 'validates input parameters' do
      expect do
        converter.convert_with_spectrogram_patterns('',
                                                    test_spectrogram)
      end.to raise_error(ArgumentError, /Text input cannot be nil or empty/)
      expect do
        converter.convert_with_spectrogram_patterns(sample_text,
                                                    'nonexistent.png')
      end.to raise_error(ArgumentError, /Spectrogram file not found/)
    end

    it 'handles meaning preservation thresholds' do
      options = { enable_rewriting: true, preserve_meaning: true, meaning_threshold: 0.95 }

      # Mock a rewriter that fails meaning preservation
      allow_any_instance_of(ProsodicTextConverter::SpeechPatternRewriter).to receive(:rewrite_text).and_return({
                                                                                                                 rewrite_applied: false,
                                                                                                                 fallback_reason: 'meaning_preservation_failed',
                                                                                                                 rewritten_text: sample_text,
                                                                                                                 rewritten_analysis: converter.instance_variable_get(:@analyzer).analyze(sample_text)
                                                                                                               })

      result = converter.convert_with_spectrogram_patterns(sample_text, test_spectrogram, options)

      expect(result[:rewrite_result][:rewrite_applied]).to be(false)
      expect(result[:rewrite_result][:fallback_reason]).to eq('meaning_preservation_failed')
    end
  end

  describe '#convert_with_intelligent_rewriting' do
    it 'generates spectrogram and performs intelligent rewriting' do
      result = converter.convert_with_intelligent_rewriting(sample_text, test_audio)

      expect(result).to be_a(Hash)
      expect(result).to have_key(:audio_file)
      expect(result).to have_key(:spectrogram_generation)
      expect(result).to have_key(:audio_analysis_backend)
      expect(result).to have_key(:speech_patterns)
      expect(result).to have_key(:rewrite_result)

      expect(result[:audio_file]).to eq(test_audio)
      expect(result[:audio_analysis_backend]).to eq(:aubio)
      expect(result[:rewrite_result][:strategy_used]).to eq('comprehensive')
    end

    it 'uses comprehensive strategy by default' do
      result = converter.convert_with_intelligent_rewriting(sample_text, test_audio)
      expect(result[:rewrite_result][:strategy_used]).to eq('comprehensive')
    end

    it 'accepts custom options' do
      options = {
        enable_rewriting: true,
        rewrite_strategy: 'stress',
        preserve_meaning: false,
        meaning_threshold: 0.7
      }

      result = converter.convert_with_intelligent_rewriting(sample_text, test_audio, options)
      expect(result[:rewrite_result][:strategy_used]).to eq('stress')
    end

    it 'validates input parameters' do
      expect do
        converter.convert_with_intelligent_rewriting('',
                                                     test_audio)
      end.to raise_error(ArgumentError, /Text input cannot be nil or empty/)
      expect do
        converter.convert_with_intelligent_rewriting(sample_text,
                                                     'nonexistent.wav')
      end.to raise_error(ArgumentError, /Audio file not found/)
    end
  end

  describe '#analyze_speech_patterns' do
    it 'extracts speech patterns without text conversion' do
      result = converter.analyze_speech_patterns(test_spectrogram, audio_file: test_audio)

      expect(result).to be_a(Hash)
      expect(result).to have_key(:speech_patterns)
      expect(result).to have_key(:spectrogram_file)
      expect(result).to have_key(:audio_file)
      expect(result).to have_key(:analysis_time)
      expect(result).to have_key(:backend_used)

      expect(result[:spectrogram_file]).to eq(test_spectrogram)
      expect(result[:audio_file]).to eq(test_audio)
      expect(result[:backend_used]).to eq(:aubio)
      expect(result[:analysis_time]).to be_a(Float)
    end

    it 'works without audio file' do
      result = converter.analyze_speech_patterns(test_spectrogram)

      expect(result[:spectrogram_file]).to eq(test_spectrogram)
      expect(result[:audio_file]).to be_nil
    end

    it 'validates spectrogram file existence' do
      expect do
        converter.analyze_speech_patterns('nonexistent.png')
      end.to raise_error(ArgumentError, /Spectrogram file not found/)
    end
  end

  describe '#generate_rewriting_guidance' do
    it 'generates guidance from speech patterns' do
      result = converter.generate_rewriting_guidance(sample_text, mock_speech_patterns)

      expect(result).to be_a(Hash)
      expect(result).to have_key(:text_analysis)
      expect(result).to have_key(:rewrite_guidance)
      expect(result).to have_key(:speech_patterns_used)
      expect(result).to have_key(:generation_time)

      expect(result[:text_analysis][:original_text]).to eq(sample_text)
      expect(result[:generation_time]).to be_a(Float)
    end

    it 'validates input parameters' do
      expect do
        converter.generate_rewriting_guidance('',
                                              mock_speech_patterns)
      end.to raise_error(ArgumentError, /Text input cannot be nil or empty/)
      expect do
        converter.generate_rewriting_guidance(sample_text,
                                              {})
      end.to raise_error(ArgumentError, /Speech patterns must contain temporal_patterns/)
      expect do
        converter.generate_rewriting_guidance(sample_text,
                                              nil)
      end.to raise_error(ArgumentError, /Speech patterns must contain temporal_patterns/)
    end
  end

  describe '#create_pattern_from_speech_analysis' do
    it 'creates prosodic pattern from speech analysis' do
      pattern = converter.send(:create_pattern_from_speech_analysis, mock_speech_patterns)

      expect(pattern).to be_a(ProsodicTextConverter::ProsodicPattern)
      expect(pattern.name).to include('extracted')
      expect(pattern.name).to include('regular')
      expect(pattern.name).to include('medium')
      expect(pattern.segment_duration).to be_between(0.5, 2.5)
      expect(pattern.pause_duration).to be_between(0.1, 1.0)
      expect(pattern.pitch_variation).to be_between(2, 15)
      expect(pattern.rate).to be_in(%w[slow medium fast])
    end

    it 'handles missing rhythm data gracefully' do
      patterns_without_rhythm = mock_speech_patterns.dup
      patterns_without_rhythm[:rhythm_patterns] = {}

      pattern = converter.send(:create_pattern_from_speech_analysis, patterns_without_rhythm)

      expect(pattern.rate).to eq('medium')
      expect(pattern.name).to include('extracted')
    end

    it 'clamps values to valid ranges' do
      extreme_patterns = {
        temporal_patterns: {
          timing_metrics: { average_duration: 10.0 }, # Too high
          transitions: [{ duration: -0.5 }] # Invalid
        },
        rhythm_patterns: {
          average_tempo: 50, # Too slow
          rhythm_regularity: 'irregular'
        },
        frequency_patterns: { pitch_contour: [] }
      }

      pattern = converter.send(:create_pattern_from_speech_analysis, extreme_patterns)

      expect(pattern.segment_duration).to eq(2.5) # Clamped to max
      expect(pattern.pause_duration).to be_between(0.1, 1.0)
      expect(pattern.rate).to eq('slow')
    end
  end

  describe 'error handling' do
    it 'handles speech pattern extraction failures' do
      allow_any_instance_of(ProsodicTextConverter::SpeechPatternExtractor).to receive(:extract_speech_patterns).and_raise(StandardError.new('Extraction failed'))

      expect do
        converter.convert_with_spectrogram_patterns(sample_text,
                                                    test_spectrogram)
      end.to raise_error(/Spectrogram-guided conversion failed/)
    end

    it 'handles rewriting failures gracefully' do
      allow_any_instance_of(ProsodicTextConverter::SpeechPatternRewriter).to receive(:rewrite_text).and_raise(StandardError.new('Rewriting failed'))

      expect do
        converter.convert_with_spectrogram_patterns(sample_text,
                                                    test_spectrogram)
      end.to raise_error(/Spectrogram-guided conversion failed/)
    end

    it 'handles spectrogram generation failures' do
      allow_any_instance_of(ProsodicTextConverter::SpectrogramGenerator).to receive(:generate).and_raise(StandardError.new('Generation failed'))

      expect do
        converter.convert_with_intelligent_rewriting(sample_text,
                                                     test_audio)
      end.to raise_error(/Intelligent rewriting conversion failed/)
    end

    it 'handles LLM conversion failures' do
      allow_any_instance_of(ProsodicTextConverter::LLMConverter).to receive(:convert_text_with_analysis).and_raise(StandardError.new('LLM failed'))

      expect do
        converter.convert_with_spectrogram_patterns(sample_text,
                                                    test_spectrogram)
      end.to raise_error(/Spectrogram-guided conversion failed/)
    end
  end

  describe 'integration with existing functionality' do
    it 'works with different pitch backends' do
      sonic_converter = described_class.new(
        pattern: :deliberate,
        provider: :gemini,
        pitch_backend: :sonic_annotator,
        output_dir: output_dir
      )

      # Mock sonic annotator components
      allow_any_instance_of(ProsodicTextConverter::SpeechPatternExtractor).to receive(:initialize).with(pitch_backend: :sonic_annotator).and_call_original

      result = sonic_converter.convert_with_spectrogram_patterns(sample_text, test_spectrogram)
      expect(result[:audio_analysis_backend]).to eq(:sonic_annotator)
    end

    it 'preserves configuration options' do
      custom_config = double('Config')
      allow(custom_config).to receive(:rephrasing_enabled?).and_return(false)

      custom_converter = described_class.new(
        provider: :openai,
        model: 'gpt-4',
        config: custom_config,
        output_dir: output_dir
      )

      result = custom_converter.convert_with_spectrogram_patterns(sample_text, test_spectrogram)
      expect(result).to have_key(:ssml_output)
    end

    it 'works with different LLM providers' do
      anthropic_converter = described_class.new(
        provider: :anthropic,
        model: 'claude-3-sonnet',
        output_dir: output_dir
      )

      result = anthropic_converter.convert_with_spectrogram_patterns(sample_text, test_spectrogram)
      expect(result).to have_key(:ssml_output)
    end
  end

  private

  def mock_spectrogram_generator
    mock_generator = double('SpectrogramGenerator')
    allow(mock_generator).to receive(:generate).and_return({
                                                             input_file: test_audio,
                                                             spectrogram_file: test_spectrogram,
                                                             generation_output: 'Generated successfully',
                                                             file_size: 1024
                                                           })
    allow_any_instance_of(described_class).to receive(:initialize_spectrogram_generator).and_return(mock_generator)
  end

  def mock_speech_pattern_extractor
    mock_extractor = double('SpeechPatternExtractor')
    allow(mock_extractor).to receive(:extract_speech_patterns).and_return(mock_speech_patterns)
    allow(mock_extractor).to receive(:generate_rewrite_guidance).and_return(mock_rewrite_guidance)
    allow(mock_extractor).to receive(:instance_variable_set)
    allow_any_instance_of(described_class).to receive(:initialize_speech_pattern_extractor).and_return(mock_extractor)
  end

  def mock_speech_pattern_rewriter
    mock_rewriter = double('SpeechPatternRewriter')
    allow(mock_rewriter).to receive(:rewrite_text).and_return({
                                                                rewritten_text: 'Hello there, world. This is an improved test sentence for speech pattern analysis.',
                                                                rewritten_analysis: converter.instance_variable_get(:@analyzer).analyze('Hello there, world. This is an improved test sentence for speech pattern analysis.'),
                                                                rewrite_applied: true,
                                                                strategy_used: 'rhythm',
                                                                processing_time: 2.5,
                                                                changes_summary: {
                                                                  length_change: 15,
                                                                  word_count_change: 2,
                                                                  sentence_count_change: 0,
                                                                  structural_changes: ['word_substitution']
                                                                }
                                                              })
    allow_any_instance_of(described_class).to receive(:initialize_speech_pattern_rewriter).and_return(mock_rewriter)
  end

  def mock_llm_converter
    mock_converter = double('LLMConverter')
    allow(mock_converter).to receive(:convert_text_with_analysis).and_return(
      '<speak><prosody rate="medium" pitch="+2%">Hello world.</prosody><break time="350ms"/><prosody rate="medium" pitch="-1%">This is a test sentence for speech pattern analysis.</prosody></speak>'
    )
    allow_any_instance_of(described_class).to receive(:initialize_llm_converter).and_return(mock_converter)
  end

  def mock_ssml_formatter
    mock_formatter = double('SSMLFormatter')
    allow(mock_formatter).to receive(:clean_ssml) { |input| input }
    allow(mock_formatter).to receive(:extract_timing_info).and_return({
                                                                        total_breaks: 1,
                                                                        total_break_time: 0.35,
                                                                        prosody_segments: 2,
                                                                        estimated_duration: 3.0
                                                                      })
    allow_any_instance_of(described_class).to receive(:initialize_ssml_formatter).and_return(mock_formatter)
  end
end
