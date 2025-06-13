# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ProsodicTextConverter::SpectrogramAnalyzer do
  let(:test_spectrogram_file) { '/path/to/test_spectrogram.png' }
  let(:test_audio_file) { '/path/to/test.wav' }
  let(:mock_pitch_analyzer) { instance_double(ProsodicTextConverter::AubioPitchAnalyzer) }
  let(:mock_image) { instance_double(MiniMagick::Image) }
  let(:mock_grayscale_image) { instance_double(MiniMagick::Image) }

  let(:sample_pitch_data) do
    [
      { timestamp: 0.0, frequency: 150.0 },
      { timestamp: 0.1, frequency: 160.0 },
      { timestamp: 0.2, frequency: 140.0 },
      { timestamp: 0.3, frequency: 170.0 }
    ]
  end

  let(:sonic_annotator_pitch_data) do
    [
      { timestamp: 0.0, frequency: 150.0, tempo_context: 120.0 },
      { timestamp: 0.1, frequency: 160.0, tempo_context: 125.0 },
      { timestamp: 0.2, frequency: 140.0, tempo_context: 115.0 }
    ]
  end

  before do
    # Mock PitchAnalyzerFactory
    allow(ProsodicTextConverter::PitchAnalyzerFactory).to receive(:create)
      .and_return(mock_pitch_analyzer)

    # Mock MiniMagick dependencies
    stub_const('MiniMagick::Image', Class.new)
    allow(MiniMagick::Image).to receive(:open).and_return(mock_image)

    # Mock image properties
    allow(mock_image).to receive(:width).and_return(800)
    allow(mock_image).to receive(:height).and_return(400)
    allow(mock_image).to receive(:dup).and_return(mock_grayscale_image)
    allow(mock_grayscale_image).to receive(:colorspace).with('Gray').and_return(mock_grayscale_image)
    allow(mock_grayscale_image).to receive(:width).and_return(800)
    allow(mock_grayscale_image).to receive(:height).and_return(400)

    # Mock file system
    allow(File).to receive(:exist?).with(test_spectrogram_file).and_return(true)
    allow(File).to receive(:exist?).with(test_audio_file).and_return(true)

    # Mock pitch analyzer
    allow(mock_pitch_analyzer).to receive(:analyze).and_return(sample_pitch_data)
    allow(mock_pitch_analyzer).to receive(:calculate_pitch_variation).and_return(5.5)
  end

  describe '#initialize' do
    context 'with default parameters' do
      it 'initializes with aubio backend' do
        expect(ProsodicTextConverter::PitchAnalyzerFactory).to receive(:create)
          .with(backend: :aubio)

        analyzer = described_class.new
        expect(analyzer.instance_variable_get(:@pitch_backend)).to eq(:aubio)
      end
    end

    context 'with custom backend' do
      it 'initializes with sonic_annotator backend' do
        expect(ProsodicTextConverter::PitchAnalyzerFactory).to receive(:create)
          .with(backend: :sonic_annotator)

        analyzer = described_class.new(pitch_backend: :sonic_annotator)
        expect(analyzer.instance_variable_get(:@pitch_backend)).to eq(:sonic_annotator)
      end
    end

    context 'when MiniMagick is not available' do
      it 'raises error during validation' do
        # Mock the require to fail
        allow_any_instance_of(described_class).to receive(:require).with('mini_magick')
                                                                   .and_raise(LoadError)

        expect { described_class.new }.to raise_error(RuntimeError, /MiniMagick gem required/)
      end
    end
  end

  describe '#analyze' do
    let(:analyzer) { described_class.new(pitch_backend: :aubio) }

    context 'with valid spectrogram file' do
      before do
        # Mock derive_audio_file_path to return test audio file
        allow(analyzer).to receive(:derive_audio_file_path).and_return(test_audio_file)
      end

      it 'performs comprehensive analysis successfully' do
        result = analyzer.analyze(test_spectrogram_file)

        expect(result).to include(
          :image_properties,
          :temporal_analysis,
          :frequency_analysis,
          :pitch_analysis,
          :prosodic_features,
          :recommended_pattern,
          :analysis_backend
        )

        expect(result[:analysis_backend]).to eq(:aubio)
        expect(result[:recommended_pattern]).to be_a(ProsodicTextConverter::ProsodicPattern)
      end

      it 'includes correct image properties' do
        result = analyzer.analyze(test_spectrogram_file)

        expect(result[:image_properties]).to eq({
                                                  width: 800,
                                                  height: 400
                                                })
      end

      it 'includes temporal analysis' do
        result = analyzer.analyze(test_spectrogram_file)

        temporal = result[:temporal_analysis]
        expect(temporal).to include(
          :total_duration,
          :segments,
          :average_segment_duration,
          :pause_pattern
        )

        expect(temporal[:total_duration]).to be_a(Float)
        expect(temporal[:segments]).to be_an(Array)
      end

      it 'includes frequency analysis with pitch data source' do
        result = analyzer.analyze(test_spectrogram_file)

        frequency = result[:frequency_analysis]
        expect(frequency).to include(
          :fundamental_range,
          :harmonic_range,
          :estimated_pitch_variation,
          :pitch_data_source,
          :backend_used
        )

        expect(frequency[:pitch_data_source]).to eq('audio_analysis')
        expect(frequency[:backend_used]).to eq(:aubio)
        expect(frequency[:estimated_pitch_variation]).to eq(5.5)
      end

      it 'includes pitch analysis data' do
        result = analyzer.analyze(test_spectrogram_file)

        expect(result[:pitch_analysis]).to eq(sample_pitch_data)
      end

      it 'includes prosodic features' do
        result = analyzer.analyze(test_spectrogram_file)

        features = result[:prosodic_features]
        expect(features).to include(
          :segment_duration,
          :pause_duration,
          :pitch_variation,
          :speaking_rate,
          :rhythm_regularity,
          :analysis_method,
          :backend_used
        )

        expect(features[:analysis_method]).to eq('audio_analysis')
      end

      it 'creates appropriate prosodic pattern' do
        result = analyzer.analyze(test_spectrogram_file)

        pattern = result[:recommended_pattern]
        expect(pattern.name).to include('extracted_via_audio_analysis_aubio')
        expect(pattern.segment_duration).to be_between(0.5, 2.0)
        expect(pattern.pause_duration).to be_between(0.1, 1.0)
        expect(pattern.pitch_variation).to be_between(2, 15)
        expect(%w[slow medium fast]).to include(pattern.rate)
      end
    end

    context 'with sonic_annotator backend' do
      let(:analyzer) { described_class.new(pitch_backend: :sonic_annotator) }

      before do
        allow(analyzer).to receive(:derive_audio_file_path).and_return(test_audio_file)
        allow(mock_pitch_analyzer).to receive(:analyze).and_return(sonic_annotator_pitch_data)
      end

      it 'includes enhanced metrics from sonic_annotator' do
        result = analyzer.analyze(test_spectrogram_file)

        features = result[:prosodic_features]
        expect(features).to include(
          :pitch_range_semitones,
          :pitch_stability,
          :voiced_segments,
          :average_pitch_hz,
          :tempo_variability
        )

        frequency = result[:frequency_analysis]
        expect(frequency).to include(
          :pitch_range_semitones,
          :pitch_stability,
          :voiced_segments,
          :average_pitch_hz,
          :tempo_variability
        )
      end

      it 'calculates advanced pitch metrics correctly' do
        result = analyzer.analyze(test_spectrogram_file)

        frequency = result[:frequency_analysis]
        expect(frequency[:pitch_range_semitones]).to be > 0
        expect(frequency[:pitch_stability]).to be_between(0, 1)
        expect(frequency[:voiced_segments]).to be >= 0
        expect(frequency[:average_pitch_hz]).to be > 0
        expect(frequency[:tempo_variability]).to be >= 0
      end
    end

    context 'when audio file is not found' do
      before do
        allow(analyzer).to receive(:derive_audio_file_path).and_return(nil)
      end

      it 'raises AnalysisError when no audio file is found' do
        expect { analyzer.analyze(test_spectrogram_file) }
          .to raise_error(ProsodicTextConverter::AnalysisError,
                          /Pitch analysis failed; cannot proceed with spectrogram-only estimation/)
      end
    end

    context 'when pitch analysis fails' do
      before do
        allow(analyzer).to receive(:derive_audio_file_path).and_return(test_audio_file)
        allow(mock_pitch_analyzer).to receive(:analyze).and_raise(StandardError, 'Analysis failed')
      end

      it 'raises AnalysisError instead of falling back to spectrogram-only analysis' do
        expect { analyzer.analyze(test_spectrogram_file) }
          .to raise_error(ProsodicTextConverter::AnalysisError,
                          /Pitch analysis failed; cannot proceed with spectrogram-only estimation/)
      end
    end

    context 'with invalid spectrogram file' do
      it 'raises error for non-existent file' do
        allow(File).to receive(:exist?).with('/nonexistent.png').and_return(false)

        expect { analyzer.analyze('/nonexistent.png') }
          .to raise_error(RuntimeError, /Spectrogram file not found/)
      end
    end
  end

  describe 'audio file derivation' do
    let(:analyzer) { described_class.new }

    describe '#derive_audio_file_path' do
      it 'finds wav file in same directory' do
        spectrogram_path = '/audio/voice_spectrogram.png'
        audio_path = '/audio/voice.wav'

        allow(File).to receive(:exist?).with(audio_path).and_return(true)
        allow(File).to receive(:exist?).and_call_original

        result = analyzer.send(:derive_audio_file_path, spectrogram_path)
        expect(result).to eq(audio_path)
      end

      it 'finds mp3 file when wav is not available' do
        spectrogram_path = '/audio/voice_spectrogram.png'
        wav_path = '/audio/voice.wav'
        mp3_path = '/audio/voice.mp3'

        allow(File).to receive(:exist?).with(wav_path).and_return(false)
        allow(File).to receive(:exist?).with(mp3_path).and_return(true)
        allow(File).to receive(:exist?).and_call_original

        result = analyzer.send(:derive_audio_file_path, spectrogram_path)
        expect(result).to eq(mp3_path)
      end

      it 'searches parent directory when not found locally' do
        spectrogram_path = '/spectrograms/voice_spectrogram.png'
        parent_audio_path = '/voice.wav'

        # No files in spectrograms directory
        allow(File).to receive(:exist?).and_return(false)
        # But file exists in parent
        allow(File).to receive(:exist?).with(parent_audio_path).and_return(true)

        result = analyzer.send(:derive_audio_file_path, spectrogram_path)
        expect(result).to eq(parent_audio_path)
      end

      it 'returns nil when audio file is not found' do
        spectrogram_path = '/spectrograms/voice_spectrogram.png'

        allow(File).to receive(:exist?).and_return(false)

        result = analyzer.send(:derive_audio_file_path, spectrogram_path)
        expect(result).to be_nil
      end
    end
  end

  describe 'temporal analysis methods' do
    let(:analyzer) { described_class.new }

    describe '#analyze_temporal_structure' do
      it 'extracts temporal features from image' do
        result = analyzer.send(:analyze_temporal_structure, mock_image)

        expect(result).to include(
          :total_duration,
          :segments,
          :average_segment_duration,
          :pause_pattern
        )

        expect(result[:total_duration]).to eq(4.0) # 800 pixels / 200 pixels per second
      end
    end

    describe '#detect_speech_segments' do
      it 'identifies speech segments from energy profile' do
        # High energy pattern: [low, high, high, low, high, low]
        energy_profile = [50, 150, 140, 60, 160, 55]

        segments = analyzer.send(:detect_speech_segments, energy_profile)

        expect(segments).to be_an(Array)
        segments.each do |segment|
          expect(segment).to include(:start, :end, :duration)
          expect(segment[:duration]).to be > 0
        end
      end

      it 'filters out very short segments' do
        # Short high energy blip
        energy_profile = [50, 150, 60, 50, 50]

        segments = analyzer.send(:detect_speech_segments, energy_profile)

        # Should filter out segments shorter than 0.1 seconds
        expect(segments.all? { |s| s[:duration] >= 0.1 }).to be true
      end
    end

    describe '#analyze_pause_pattern' do
      let(:sample_segments) do
        [
          { start: 0.0, end: 1.0, duration: 1.0 },
          { start: 1.5, end: 2.5, duration: 1.0 },
          { start: 3.0, end: 4.0, duration: 1.0 }
        ]
      end

      it 'calculates pause statistics from segments' do
        result = analyzer.send(:analyze_pause_pattern, sample_segments)

        expect(result).to include(:average_pause, :pause_count, :pause_variance)
        expect(result[:average_pause]).to eq(0.5) # (1.5-1.0 + 3.0-2.5) / 2
        expect(result[:pause_count]).to eq(2)
      end

      it 'handles single segment gracefully' do
        single_segment = [{ start: 0.0, end: 1.0, duration: 1.0 }]

        result = analyzer.send(:analyze_pause_pattern, single_segment)

        expect(result[:average_pause]).to eq(0.35) # Default value
      end
    end
  end

  describe 'frequency analysis methods' do
    let(:analyzer) { described_class.new(pitch_backend: :sonic_annotator) }

    describe '#extract_advanced_pitch_metrics' do
      it 'calculates comprehensive pitch metrics' do
        result = analyzer.send(:extract_advanced_pitch_metrics, sonic_annotator_pitch_data)

        expect(result).to include(
          :pitch_range_semitones,
          :pitch_stability,
          :voiced_segments,
          :average_pitch_hz,
          :tempo_variability
        )

        expect(result[:pitch_range_semitones]).to be > 0
        expect(result[:average_pitch_hz]).to be_within(1).of(150)
      end

      it 'handles insufficient data gracefully' do
        short_data = [{ timestamp: 0.0, frequency: 150.0 }]

        result = analyzer.send(:extract_advanced_pitch_metrics, short_data)

        expect(result).to eq({})
      end
    end

    describe '#calculate_pitch_range_semitones' do
      it 'calculates pitch range in semitones' do
        frequencies = [100.0, 200.0] # One octave = 12 semitones

        result = analyzer.send(:calculate_pitch_range_semitones, frequencies)

        expect(result).to be_within(0.1).of(12.0)
      end

      it 'handles empty array' do
        result = analyzer.send(:calculate_pitch_range_semitones, [])
        expect(result).to eq(0)
      end
    end

    describe '#calculate_pitch_stability' do
      it 'measures pitch contour stability' do
        stable_data = [
          { frequency: 150.0 },
          { frequency: 151.0 },
          { frequency: 149.0 }
        ]

        result = analyzer.send(:calculate_pitch_stability, stable_data)

        expect(result).to be_between(0.8, 1.0) # High stability
      end

      it 'detects unstable pitch' do
        unstable_data = [
          { frequency: 100.0 },
          { frequency: 200.0 },
          { frequency: 100.0 }
        ]

        result = analyzer.send(:calculate_pitch_stability, unstable_data)

        expect(result).to be < 0.5 # Low stability
      end
    end

    describe '#count_voiced_segments' do
      it 'counts continuous voiced regions' do
        pitch_data = [
          { frequency: 150.0 },
          { frequency: 160.0 },
          { frequency: 0.0 },    # Unvoiced
          { frequency: 140.0 },
          { frequency: 0.0 },    # Unvoiced
          { frequency: 170.0 }
        ]

        result = analyzer.send(:count_voiced_segments, pitch_data)

        expect(result).to eq(3)  # Three separate voiced segments
      end
    end
  end

  describe 'prosodic feature extraction' do
    let(:analyzer) { described_class.new }

    let(:temporal_analysis) do
      {
        average_segment_duration: 1.2,
        pause_pattern: { average_pause: 0.4 },
        segments: [
          { duration: 1.0 },
          { duration: 1.2 },
          { duration: 1.4 }
        ]
      }
    end

    let(:frequency_analysis) do
      {
        estimated_pitch_variation: 6.5,
        pitch_data_source: 'audio_analysis',
        backend_used: :aubio
      }
    end

    describe '#extract_prosodic_features' do
      it 'combines temporal and frequency features' do
        result = analyzer.send(:extract_prosodic_features, temporal_analysis, frequency_analysis, sample_pitch_data)

        expect(result).to include(
          :segment_duration,
          :pause_duration,
          :pitch_variation,
          :speaking_rate,
          :rhythm_regularity,
          :analysis_method,
          :backend_used
        )

        expect(result[:segment_duration]).to eq(1.2)
        expect(result[:pause_duration]).to eq(0.4)
        expect(result[:pitch_variation]).to eq(6.5)
        expect(result[:speaking_rate]).to eq('slow') # 1.2s is slow
      end

      it 'clamps values to reasonable ranges' do
        extreme_temporal = {
          average_segment_duration: 5.0, # Too long
          pause_pattern: { average_pause: 2.0 }, # Too long
          segments: []
        }

        extreme_frequency = {
          estimated_pitch_variation: 50.0, # Too high
          pitch_data_source: 'test',
          backend_used: :aubio
        }

        result = analyzer.send(:extract_prosodic_features, extreme_temporal, extreme_frequency, nil)

        expect(result[:segment_duration]).to eq(2.0)  # Clamped to max
        expect(result[:pause_duration]).to eq(1.0)    # Clamped to max
        expect(result[:pitch_variation]).to eq(15)    # Clamped to max
      end
    end

    describe '#determine_speaking_rate' do
      it 'categorizes speaking rates correctly' do
        expect(analyzer.send(:determine_speaking_rate, 0.6)).to eq('fast')
        expect(analyzer.send(:determine_speaking_rate, 0.9)).to eq('medium')
        expect(analyzer.send(:determine_speaking_rate, 1.5)).to eq('slow')
      end
    end

    describe '#assess_rhythm_regularity' do
      it 'assesses rhythm from segment durations' do
        regular_segments = [
          { duration: 1.0 },
          { duration: 1.0 },
          { duration: 1.0 }
        ]

        result = analyzer.send(:assess_rhythm_regularity, regular_segments)
        expect(result).to eq('very_regular')

        irregular_segments = [
          { duration: 0.5 },
          { duration: 2.0 },
          { duration: 0.8 }
        ]

        result = analyzer.send(:assess_rhythm_regularity, irregular_segments)
        expect(result).to eq('irregular')
      end

      it 'handles insufficient segments' do
        few_segments = [{ duration: 1.0 }]

        result = analyzer.send(:assess_rhythm_regularity, few_segments)
        expect(result).to eq('regular')
      end
    end
  end

  describe '#create_prosodic_pattern' do
    let(:analyzer) { described_class.new }

    let(:sample_features) do
      {
        segment_duration: 1.0,
        pause_duration: 0.35,
        pitch_variation: 5,
        speaking_rate: 'medium',
        analysis_method: 'audio_analysis',
        backend_used: :aubio
      }
    end

    it 'creates ProsodicPattern from features' do
      pattern = analyzer.send(:create_prosodic_pattern, sample_features)

      expect(pattern).to be_a(ProsodicTextConverter::ProsodicPattern)
      expect(pattern.name).to eq('extracted_via_audio_analysis_aubio')
      expect(pattern.segment_duration).to eq(1.0)
      expect(pattern.pause_duration).to eq(0.35)
      expect(pattern.pitch_variation).to eq(5)
      expect(pattern.rate).to eq('medium')
    end
  end

  describe 'utility methods' do
    let(:analyzer) { described_class.new }

    describe '#estimate_duration_from_width' do
      it 'estimates duration from image width' do
        # 800 pixels at 200 pixels/second = 4 seconds
        duration = analyzer.send(:estimate_duration_from_width, 800)
        expect(duration).to eq(4.0)
      end
    end

    describe '#calculate_variance' do
      it 'calculates standard deviation correctly' do
        values = [1.0, 2.0, 3.0]
        variance = analyzer.send(:calculate_variance, values)

        # Standard deviation of [1,2,3] is approximately 0.816
        expect(variance).to be_within(0.01).of(0.816)
      end

      it 'handles empty array' do
        variance = analyzer.send(:calculate_variance, [])
        expect(variance).to eq(0)
      end
    end
  end
end
