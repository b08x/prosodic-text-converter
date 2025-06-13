# frozen_string_literal: true

require 'spec_helper'
require 'prosodic-text-converter/analysis/speech_pattern_extractor'
require 'prosodic-text-converter/text/text_analyzer'

RSpec.describe ProsodicTextConverter::SpeechPatternExtractor do
  let(:test_files_dir) { File.join(__dir__, '..', 'test_files') }
  let(:test_spectrogram) { File.join(test_files_dir, 'test_spectrogram.png') }
  let(:test_audio) { File.join(test_files_dir, 'test_audio.wav') }
  let(:extractor) { described_class.new(pitch_backend: :aubio) }
  let(:text_analyzer) { ProsodicTextConverter::TextAnalyzer.new }

  before do
    # Create test files directory if it doesn't exist
    FileUtils.mkdir_p(test_files_dir) unless Dir.exist?(test_files_dir)
    
    # Create a simple test spectrogram file (placeholder)
    unless File.exist?(test_spectrogram)
      File.write(test_spectrogram, 'PNG_PLACEHOLDER')
    end
    
    # Create a simple test audio file (placeholder) 
    unless File.exist?(test_audio)
      File.write(test_audio, 'WAV_PLACEHOLDER')
    end
  end

  describe '#initialize' do
    it 'initializes with default options' do
      expect(extractor).to be_a(described_class)
      expect(extractor.extracted_patterns).to be_empty
    end

    it 'accepts custom options' do
      custom_extractor = described_class.new(
        pitch_backend: :sonic_annotator,
        options: {
          detailed_analysis: false,
          emotional_detection: false,
          rhythm_sensitivity: 0.5
        }
      )
      expect(custom_extractor).to be_a(described_class)
    end

    it 'raises error for missing dependencies' do
      allow_any_instance_of(described_class).to receive(:require).with('mini_magick').and_raise(LoadError)
      expect { described_class.new }.to raise_error(/MiniMagick gem required/)
    end
  end

  describe '#extract_speech_patterns' do
    let(:mock_image) do
      double('MiniMagick::Image', width: 1000, height: 500, dup: double('Image', colorspace: double('GrayImage')))
    end

    before do
      allow(File).to receive(:exist?).with(test_spectrogram).and_return(true)
      allow(MiniMagick::Image).to receive(:open).with(test_spectrogram).and_return(mock_image)
      allow(extractor).to receive(:analyze_pitch_from_audio).and_return([
        { timestamp: 0.0, frequency: 150.0, confidence: 0.9 },
        { timestamp: 0.1, frequency: 155.0, confidence: 0.8 },
        { timestamp: 0.2, frequency: 160.0, confidence: 0.9 }
      ])
    end

    it 'extracts comprehensive speech patterns from spectrogram' do
      result = extractor.extract_speech_patterns(test_spectrogram)

      expect(result).to be_a(Hash)
      expect(result).to have_key(:temporal_patterns)
      expect(result).to have_key(:frequency_patterns)
      expect(result).to have_key(:rhythm_patterns)
      expect(result).to have_key(:stress_patterns)
      expect(result).to have_key(:intonation_patterns)
      expect(result).to have_key(:emotional_patterns)
      expect(result).to have_key(:breathing_patterns)
      expect(result).to have_key(:extraction_metadata)
    end

    it 'includes extraction metadata' do
      result = extractor.extract_speech_patterns(test_spectrogram, audio_file: test_audio)

      metadata = result[:extraction_metadata]
      expect(metadata[:spectrogram_file]).to eq(test_spectrogram)
      expect(metadata[:audio_file]).to eq(test_audio)
      expect(metadata[:backend_used]).to eq(:aubio)
      expect(metadata[:extraction_time]).to be_a(Float)
      expect(metadata[:detailed_analysis]).to be(true)
    end

    it 'handles missing spectrogram file' do
      expect { extractor.extract_speech_patterns('nonexistent.png') }.to raise_error(/Spectrogram file not found/)
    end

    it 'derives audio file path from spectrogram filename' do
      allow(extractor).to receive(:derive_audio_file_path).with(test_spectrogram).and_return(test_audio)
      allow(File).to receive(:exist?).with(test_audio).and_return(true)
      
      result = extractor.extract_speech_patterns(test_spectrogram)
      expect(result[:extraction_metadata][:audio_file]).to eq(test_audio)
    end
  end

  describe '#generate_rewrite_guidance' do
    let(:sample_text) { "Hello world. This is a test sentence for analysis." }
    let(:text_analysis) { text_analyzer.analyze(sample_text) }
    let(:mock_patterns) do
      {
        temporal_patterns: {
          total_duration: 3.0,
          segments: [
            { start: 0.0, end: 1.0, duration: 1.0 },
            { start: 1.2, end: 2.5, duration: 1.3 }
          ],
          timing_metrics: { average_duration: 1.15 },
          speech_to_silence_ratio: 2.5,
          segment_regularity: 'regular'
        },
        frequency_patterns: {
          pitch_contour: [
            { time: 0.0, frequency: 150.0 },
            { time: 1.0, frequency: 155.0 },
            { time: 2.0, frequency: 160.0 }
          ]
        },
        rhythm_patterns: {
          average_tempo: 120,
          rhythm_regularity: 'regular',
          rhythm_complexity: 'moderate'
        },
        stress_patterns: {
          primary_stress_pattern: 'iambic',
          stress_density: 0.6,
          stress_regularity: 'regular'
        },
        intonation_patterns: {
          available: true,
          overall_contour_shape: 'rising',
          boundary_tones: { initial: 150.0, final: 160.0 }
        },
        emotional_patterns: {
          available: true,
          emotional_state: 'neutral',
          arousal_level: 0.5,
          valence_level: 0.5
        },
        breathing_patterns: {
          breath_pauses: [{ start: 1.0, duration: 0.2, type: 'breath' }],
          breathing_regularity: 'regular'
        }
      }
    end

    before do
      extractor.instance_variable_set(:@extracted_patterns, mock_patterns)
    end

    it 'generates comprehensive rewriting guidance' do
      guidance = extractor.generate_rewrite_guidance(text_analysis)

      expect(guidance).to be_a(Hash)
      expect(guidance).to have_key(:overall_strategy)
      expect(guidance).to have_key(:sentence_guidance)
      expect(guidance).to have_key(:rhythm_adjustments)
      expect(guidance).to have_key(:stress_adjustments)
      expect(guidance).to have_key(:intonation_guidance)
      expect(guidance).to have_key(:pacing_recommendations)
      expect(guidance).to have_key(:emotional_alignment)
      expect(guidance).to have_key(:prosodic_targets)
    end

    it 'determines appropriate overall strategy' do
      guidance = extractor.generate_rewrite_guidance(text_analysis)
      
      strategy = guidance[:overall_strategy]
      expect(strategy).to have_key(:primary_focus)
      expect(strategy).to have_key(:rewrite_aggressiveness)
      expect(strategy).to have_key(:rhythm_priority)
      expect(strategy).to have_key(:stress_priority)
      expect(strategy).to have_key(:intonation_priority)
      expect(strategy[:primary_focus]).to be_in(['rhythm', 'stress', 'intonation'])
    end

    it 'generates sentence-level guidance' do
      guidance = extractor.generate_rewrite_guidance(text_analysis)
      
      sentence_guidance = guidance[:sentence_guidance]
      expect(sentence_guidance).to be_an(Array)
      expect(sentence_guidance.length).to eq(text_analysis[:sentence_count])
      
      first_sentence = sentence_guidance.first
      expect(first_sentence).to have_key(:sentence_index)
      expect(first_sentence).to have_key(:original_text)
      expect(first_sentence).to have_key(:recommended_changes)
      expect(first_sentence).to have_key(:target_timing)
      expect(first_sentence).to have_key(:stress_recommendations)
      expect(first_sentence).to have_key(:pause_recommendations)
    end

    it 'includes emotional alignment when available' do
      guidance = extractor.generate_rewrite_guidance(text_analysis)
      
      emotional_alignment = guidance[:emotional_alignment]
      expect(emotional_alignment[:available]).to be(true)
      expect(emotional_alignment).to have_key(:target_emotion)
      expect(emotional_alignment).to have_key(:arousal_target)
      expect(emotional_alignment).to have_key(:valence_target)
      expect(emotional_alignment).to have_key(:alignment_strategy)
    end

    it 'handles missing speech patterns gracefully' do
      extractor.instance_variable_set(:@extracted_patterns, {})
      
      expect { extractor.generate_rewrite_guidance(text_analysis) }.to raise_error(/No speech patterns extracted/)
    end
  end

  describe 'pattern analysis methods' do
    let(:mock_image) do
      double('MiniMagick::Image', width: 1000, height: 500, dup: double('Image', colorspace: double('GrayImage')))
    end

    describe '#extract_temporal_patterns' do
      it 'analyzes temporal structure from spectrogram' do
        result = extractor.send(:extract_temporal_patterns, mock_image)
        
        expect(result).to have_key(:total_duration)
        expect(result).to have_key(:segments)
        expect(result).to have_key(:average_segment_duration)
        expect(result).to have_key(:pause_pattern)
        expect(result[:total_duration]).to be_a(Float)
        expect(result[:segments]).to be_an(Array)
      end
    end

    describe '#extract_rhythm_patterns' do
      let(:temporal_patterns) do
        {
          segments: [
            { start: 0.0, end: 1.0, duration: 1.0 },
            { start: 1.2, end: 2.5, duration: 1.3 },
            { start: 2.8, end: 3.8, duration: 1.0 }
          ]
        }
      end

      it 'extracts rhythm patterns from temporal analysis' do
        result = extractor.send(:extract_rhythm_patterns, mock_image, temporal_patterns)
        
        expect(result).to have_key(:onset_intervals)
        expect(result).to have_key(:rhythm_regularity)
        expect(result).to have_key(:rhythmic_groups)
        expect(result).to have_key(:average_tempo)
        expect(result).to have_key(:rhythm_complexity)
        expect(result[:rhythm_regularity]).to be_in(['very_regular', 'regular', 'irregular'])
      end
    end

    describe '#extract_stress_patterns' do
      let(:frequency_patterns) do
        {
          pitch_contour: [
            { time: 0.0, frequency: 150.0 },
            { time: 1.0, frequency: 160.0 },
            { time: 2.0, frequency: 155.0 }
          ]
        }
      end

      it 'extracts stress patterns from frequency analysis' do
        result = extractor.send(:extract_stress_patterns, mock_image, frequency_patterns)
        
        expect(result).to have_key(:stress_markers)
        expect(result).to have_key(:stress_timing)
        expect(result).to have_key(:stress_regularity)
        expect(result).to have_key(:primary_stress_pattern)
        expect(result).to have_key(:stress_density)
      end
    end

    describe '#extract_intonation_patterns' do
      let(:mock_pitch_analysis) do
        [
          { timestamp: 0.0, frequency: 150.0 },
          { timestamp: 0.5, frequency: 155.0 },
          { timestamp: 1.0, frequency: 160.0 },
          { timestamp: 1.5, frequency: 155.0 },
          { timestamp: 2.0, frequency: 150.0 }
        ]
      end

      before do
        allow(extractor).to receive(:analyze_pitch_from_audio).and_return(mock_pitch_analysis)
      end

      it 'extracts intonation patterns when pitch data is available' do
        result = extractor.send(:extract_intonation_patterns, mock_image, test_audio)
        
        expect(result[:available]).to be(true)
        expect(result).to have_key(:pitch_contours)
        expect(result).to have_key(:intonation_phrases)
        expect(result).to have_key(:pitch_movements)
        expect(result).to have_key(:overall_contour_shape)
        expect(result).to have_key(:boundary_tones)
      end

      it 'handles missing pitch data gracefully' do
        allow(extractor).to receive(:analyze_pitch_from_audio).and_return(nil)
        
        result = extractor.send(:extract_intonation_patterns, mock_image, test_audio)
        expect(result[:available]).to be(false)
      end
    end
  end

  describe 'utility methods' do
    describe '#classify_overall_contour_shape' do
      it 'classifies rising contours' do
        contours = [
          { time: 0.0, frequency: 150.0 },
          { time: 1.0, frequency: 180.0 }
        ]
        
        result = extractor.send(:classify_overall_contour_shape, contours)
        expect(result).to eq('rising')
      end

      it 'classifies falling contours' do
        contours = [
          { time: 0.0, frequency: 180.0 },
          { time: 1.0, frequency: 150.0 }
        ]
        
        result = extractor.send(:classify_overall_contour_shape, contours)
        expect(result).to eq('falling')
      end

      it 'classifies flat contours' do
        contours = [
          { time: 0.0, frequency: 150.0 },
          { time: 1.0, frequency: 152.0 }
        ]
        
        result = extractor.send(:classify_overall_contour_shape, contours)
        expect(result).to eq('flat')
      end

      it 'handles empty contours' do
        result = extractor.send(:classify_overall_contour_shape, [])
        expect(result).to eq('flat')
      end
    end

    describe '#calculate_variance' do
      it 'calculates variance correctly' do
        values = [1.0, 2.0, 3.0, 4.0, 5.0]
        result = extractor.send(:calculate_variance, values)
        expect(result).to be_a(Float)
        expect(result).to be > 0
      end

      it 'handles empty arrays' do
        result = extractor.send(:calculate_variance, [])
        expect(result).to eq(0)
      end

      it 'handles single values' do
        result = extractor.send(:calculate_variance, [5.0])
        expect(result).to eq(0)
      end
    end

    describe '#derive_audio_file_path' do
      it 'finds audio file with same base name' do
        spectrogram_path = '/path/to/audio_spectrogram.png'
        expected_audio = '/path/to/audio.wav'
        
        allow(File).to receive(:exist?).with(expected_audio).and_return(true)
        
        result = extractor.send(:derive_audio_file_path, spectrogram_path)
        expect(result).to eq(expected_audio)
      end

      it 'tries multiple audio extensions' do
        spectrogram_path = '/path/to/audio_spectrogram.png'
        
        allow(File).to receive(:exist?).and_return(false)
        allow(File).to receive(:exist?).with('/path/to/audio.flac').and_return(true)
        
        result = extractor.send(:derive_audio_file_path, spectrogram_path)
        expect(result).to eq('/path/to/audio.flac')
      end

      it 'checks parent directory if not found' do
        spectrogram_path = '/path/to/spectrograms/audio_spectrogram.png'
        expected_audio = '/path/to/audio.wav'
        
        allow(File).to receive(:exist?).and_return(false)
        allow(File).to receive(:exist?).with(expected_audio).and_return(true)
        
        result = extractor.send(:derive_audio_file_path, spectrogram_path)
        expect(result).to eq(expected_audio)
      end

      it 'returns nil if no audio file found' do
        spectrogram_path = '/path/to/audio_spectrogram.png'
        
        allow(File).to receive(:exist?).and_return(false)
        
        result = extractor.send(:derive_audio_file_path, spectrogram_path)
        expect(result).to be_nil
      end
    end
  end

  describe 'error handling' do
    it 'handles MiniMagick errors gracefully' do
      allow(MiniMagick::Image).to receive(:open).and_raise(MiniMagick::Error.new('Invalid image'))
      
      expect { extractor.extract_speech_patterns(test_spectrogram) }.to raise_error(/Invalid image/)
    end

    it 'handles pitch analysis failures gracefully' do
      allow(File).to receive(:exist?).with(test_spectrogram).and_return(true)
      allow(MiniMagick::Image).to receive(:open).and_return(
        double('Image', width: 1000, height: 500, dup: double('Image', colorspace: double('GrayImage')))
      )
      allow(extractor).to receive(:analyze_pitch_from_audio).and_raise(StandardError.new('Pitch analysis failed'))
      
      result = extractor.extract_speech_patterns(test_spectrogram, audio_file: test_audio)
      expect(result[:intonation_patterns][:available]).to be(false)
    end
  end

  describe 'integration with different backends' do
    context 'with sonic_annotator backend' do
      let(:sonic_extractor) { described_class.new(pitch_backend: :sonic_annotator) }
      let(:mock_pitch_analysis) do
        [
          { timestamp: 0.0, frequency: 150.0, tempo_context: 120 },
          { timestamp: 0.1, frequency: 155.0, tempo_context: 125 },
          { timestamp: 0.2, frequency: 160.0, tempo_context: 118 }
        ]
      end

      before do
        allow(sonic_extractor).to receive(:analyze_pitch_from_audio).and_return(mock_pitch_analysis)
      end

      it 'extracts advanced metrics with sonic_annotator' do
        allow(File).to receive(:exist?).with(test_spectrogram).and_return(true)
        allow(MiniMagick::Image).to receive(:open).and_return(
          double('Image', width: 1000, height: 500, dup: double('Image', colorspace: double('GrayImage')))
        )
        
        result = sonic_extractor.extract_speech_patterns(test_spectrogram, audio_file: test_audio)
        
        frequency_patterns = result[:frequency_patterns]
        expect(frequency_patterns).to have_key(:advanced_pitch_metrics)
        
        advanced_metrics = frequency_patterns[:advanced_pitch_metrics]
        expect(advanced_metrics).to have_key(:pitch_range_hz)
        expect(advanced_metrics).to have_key(:pitch_stability)
        expect(advanced_metrics).to have_key(:jitter)
        expect(advanced_metrics).to have_key(:shimmer)
      end
    end
  end
end