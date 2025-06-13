# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ProsodicTextConverter::Converter do
  let(:test_text) { 'Hello world. This is a test.' }
  let(:test_audio_file) { '/path/to/test_audio.wav' }
  let(:test_output_dir) { './test_spectrograms' }

  # Mock dependencies
  let(:mock_text_analyzer) { instance_double(ProsodicTextConverter::TextAnalyzer) }
  let(:mock_llm_converter) { instance_double(ProsodicTextConverter::LLMConverter) }
  let(:mock_ssml_formatter) { instance_double(ProsodicTextConverter::SSMLFormatter) }
  let(:mock_spectrogram_generator) { instance_double(ProsodicTextConverter::SpectrogramGenerator) }
  let(:mock_spectrogram_analyzer) { instance_double(ProsodicTextConverter::SpectrogramAnalyzer) }
  let(:mock_pattern) { instance_double(ProsodicTextConverter::ProsodicPattern) }
  let(:mock_logger) { instance_double(Logger) }

  # Sample data
  let(:text_analysis) do
    {
      sentence_count: 2,
      sentences: ['Hello world.', 'This is a test.'],
      tokens: %w[Hello world This is a test],
      pause_indicators: ['.']
    }
  end

  let(:ssml_output) do
    '<speak><prosody rate="medium">Hello world.</prosody><break time="350ms"/><prosody rate="medium">This is a test.</prosody></speak>'
  end
  let(:validated_ssml) { ssml_output }
  let(:timing_info) { { total_duration: 3.5, break_count: 1, segment_count: 2 } }

  let(:spectrogram_result) do
    {
      spectrogram_file: '/path/to/spectrogram.png',
      audio_duration: 2.5,
      status: 'success'
    }
  end

  let(:analysis_result) do
    {
      recommended_pattern: mock_pattern,
      pitch_variation: 5.2,
      tempo_analysis: { bpm: 120 },
      confidence: 0.85
    }
  end

  before do
    # Mock logger methods
    allow(mock_logger).to receive(:info)
    allow(mock_logger).to receive(:debug)
    allow(mock_logger).to receive(:error)
    allow(mock_logger).to receive(:warn)

    # Mock pattern methods
    allow(mock_pattern).to receive(:name).and_return('extracted')
    allow(mock_pattern).to receive(:to_h).and_return({
                                                       name: 'extracted',
                                                       segment_duration: 1.0,
                                                       pause_duration: 0.3,
                                                       pitch_variation: 5,
                                                       rate: 'medium'
                                                     })

    # Mock factory method
    allow(ProsodicTextConverter::PitchAnalyzerFactory).to receive(:available_backends)
      .and_return(%i[aubio sonic_annotator])

    # Mock component initialization
    allow(ProsodicTextConverter::TextAnalyzer).to receive(:new).and_return(mock_text_analyzer)
    allow(ProsodicTextConverter::LLMConverter).to receive(:new).and_return(mock_llm_converter)
    allow(ProsodicTextConverter::SSMLFormatter).to receive(:new).and_return(mock_ssml_formatter)
    allow(ProsodicTextConverter::SpectrogramGenerator).to receive(:new).and_return(mock_spectrogram_generator)
    allow(ProsodicTextConverter::SpectrogramAnalyzer).to receive(:new).and_return(mock_spectrogram_analyzer)

    # Mock File operations
    allow(File).to receive(:exist?).and_return(false)
    allow(File).to receive(:exist?).with(test_audio_file).and_return(true)
    allow(File).to receive(:readable?).with(test_audio_file).and_return(true)
    allow(File).to receive(:writable?).and_return(true)
    allow(Dir).to receive(:exist?).and_return(true)
    allow(FileUtils).to receive(:mkdir_p)
  end

  describe '#initialize' do
    context 'with valid parameters' do
      it 'initializes successfully with default parameters' do
        converter = described_class.new(logger: mock_logger)

        expect(converter.logger).to eq(mock_logger)
        expect(converter.pitch_backend).to eq(:aubio)
      end

      it 'initializes with custom parameters' do
        converter = described_class.new(
          provider: :openai,
          model: 'gpt-4',
          pitch_backend: :sonic_annotator,
          logger: mock_logger
        )

        expect(converter.pitch_backend).to eq(:sonic_annotator)
      end

      it 'validates pitch backend availability' do
        expect(ProsodicTextConverter::PitchAnalyzerFactory).to receive(:available_backends)
          .and_return([:aubio])

        expect do
          described_class.new(pitch_backend: :invalid_backend, logger: mock_logger)
        end.to raise_error(RuntimeError, /Pitch backend 'invalid_backend' not available/)
      end
    end

    context 'with no available backends' do
      it 'raises error when no backends are available' do
        allow(ProsodicTextConverter::PitchAnalyzerFactory).to receive(:available_backends)
          .and_return([])

        expect do
          described_class.new(logger: mock_logger)
        end.to raise_error(RuntimeError, /No pitch analysis backends available/)
      end
    end

    context 'when component initialization fails' do
      it 'raises error with informative message' do
        allow(ProsodicTextConverter::TextAnalyzer).to receive(:new)
          .and_raise(StandardError, 'Text analyzer failed')

        expect do
          described_class.new(logger: mock_logger)
        end.to raise_error(RuntimeError, /Converter initialization failed.*Text analyzer failed/)
      end
    end
  end

  describe '#convert' do
    let(:converter) { described_class.new(logger: mock_logger) }

    before do
      # Setup successful component responses
      allow(mock_text_analyzer).to receive(:analyze).with(test_text).and_return(text_analysis)
      allow(mock_llm_converter).to receive(:convert_text_with_analysis)
        .with(text_analysis, anything).and_return(ssml_output)
      allow(mock_ssml_formatter).to receive(:clean_ssml).with(ssml_output).and_return(validated_ssml)
      allow(mock_ssml_formatter).to receive(:extract_timing_info).with(validated_ssml).and_return(timing_info)
    end

    context 'with valid text' do
      it 'successfully converts text to SSML' do
        result = converter.convert(test_text)

        expect(result).to include(
          original_text: test_text,
          ssml_output: validated_ssml,
          timing_analysis: timing_info,
          sentences_processed: 2
        )
        expect(result[:pattern_used]).to include(:segment_duration, :pause_duration, :pitch_variation, :rate)
        expect(result[:conversion_time]).to be_a(Float)
        expect(result[:conversion_time]).to be > 0
      end

      it 'calls components in correct order' do
        expect(mock_text_analyzer).to receive(:analyze).with(test_text).ordered
        expect(mock_llm_converter).to receive(:convert_text_with_analysis).ordered
        expect(mock_ssml_formatter).to receive(:clean_ssml).ordered
        expect(mock_ssml_formatter).to receive(:extract_timing_info).ordered

        converter.convert(test_text)
      end
    end

    context 'with invalid text input' do
      it 'raises error for nil text' do
        expect { converter.convert(nil) }.to raise_error(ArgumentError, /Text input cannot be nil or empty/)
      end

      it 'raises error for empty text' do
        expect { converter.convert('   ') }.to raise_error(ArgumentError, /Text input cannot be nil or empty/)
      end

      it 'raises error for text that is too long' do
        long_text = 'a' * 50_001
        expect { converter.convert(long_text) }.to raise_error(ArgumentError, /Text input too long/)
      end
    end

    context 'when text analysis times out' do
      it 'raises timeout error' do
        allow(mock_text_analyzer).to receive(:analyze) do
          sleep(0.1)
          raise Timeout::Error, 'Analysis timeout'
        end

        expect { converter.convert(test_text) }.to raise_error(RuntimeError, /Text conversion timed out/)
      end
    end

    context 'when LLM conversion fails' do
      it 'raises error with context' do
        allow(mock_llm_converter).to receive(:convert_text_with_analysis)
          .and_raise(StandardError, 'LLM service unavailable')

        expect do
          converter.convert(test_text)
        end.to raise_error(RuntimeError, /Text conversion failed.*LLM service unavailable/)
      end
    end
  end

  describe '#extract_pattern_from_audio' do
    let(:converter) { described_class.new(logger: mock_logger) }

    before do
      allow(mock_spectrogram_generator).to receive(:generate)
        .with(test_audio_file, output_dir: './spectrograms').and_return(spectrogram_result)
      allow(mock_spectrogram_analyzer).to receive(:analyze)
        .with(spectrogram_result[:spectrogram_file]).and_return(analysis_result)
    end

    context 'with valid audio file' do
      it 'successfully extracts pattern from audio' do
        result = converter.extract_pattern_from_audio(test_audio_file, output_dir: test_output_dir)

        expect(result).to include(
          audio_file: test_audio_file,
          spectrogram_file: spectrogram_result[:spectrogram_file],
          analysis: analysis_result,
          extracted_pattern: hash_including(:name),
          pitch_backend_used: :aubio
        )
        expect(result[:analysis_time]).to be_a(Float)
      end

      it 'updates internal pattern from analysis' do
        converter.extract_pattern_from_audio(test_audio_file)

        expect(converter.pattern).to eq(mock_pattern)
      end

      it 'calls components in correct order' do
        expect(mock_spectrogram_generator).to receive(:generate).ordered
        expect(mock_spectrogram_analyzer).to receive(:analyze).ordered

        converter.extract_pattern_from_audio(test_audio_file)
      end
    end

    context 'with invalid audio file' do
      it 'raises error for non-existent file' do
        allow(File).to receive(:exist?).with('/nonexistent.wav').and_return(false)

        expect do
          converter.extract_pattern_from_audio('/nonexistent.wav')
        end.to raise_error(ArgumentError, /Audio file not found/)
      end

      it 'raises error for unreadable file' do
        allow(File).to receive(:readable?).with(test_audio_file).and_return(false)

        expect do
          converter.extract_pattern_from_audio(test_audio_file)
        end.to raise_error(ArgumentError, /Audio file not readable/)
      end
    end

    context 'when spectrogram generation times out' do
      it 'raises timeout error' do
        allow(mock_spectrogram_generator).to receive(:generate) do
          sleep(0.1)
          raise Timeout::Error, 'Generation timeout'
        end

        expect do
          converter.extract_pattern_from_audio(test_audio_file)
        end.to raise_error(RuntimeError, /Audio analysis timed out/)
      end
    end

    context 'when analysis fails' do
      it 'raises error with context' do
        allow(mock_spectrogram_analyzer).to receive(:analyze)
          .and_raise(StandardError, 'Analysis failed')

        expect do
          converter.extract_pattern_from_audio(test_audio_file)
        end.to raise_error(RuntimeError, /Audio analysis failed.*Analysis failed/)
      end
    end
  end

  describe '#convert_with_audio_analysis' do
    let(:converter) { described_class.new(logger: mock_logger) }

    before do
      # Mock audio analysis components
      allow(mock_spectrogram_generator).to receive(:generate).and_return(spectrogram_result)
      allow(mock_spectrogram_analyzer).to receive(:analyze).and_return(analysis_result)

      # Mock text conversion components
      allow(mock_text_analyzer).to receive(:analyze).and_return(text_analysis)
      allow(mock_llm_converter).to receive(:convert_text_with_analysis).and_return(ssml_output)
      allow(mock_ssml_formatter).to receive(:clean_ssml).and_return(validated_ssml)
      allow(mock_ssml_formatter).to receive(:extract_timing_info).and_return(timing_info)
    end

    context 'with valid inputs' do
      it 'successfully combines audio analysis and text conversion' do
        result = converter.convert_with_audio_analysis(test_text, test_audio_file)

        expect(result).to include(
          original_text: test_text,
          ssml_output: validated_ssml,
          pattern_source: 'extracted_from_audio',
          audio_analysis: hash_including(:audio_file, :analysis),
          total_processing_time: be_a(Float)
        )
      end

      it 'performs audio analysis before text conversion' do
        expect(mock_spectrogram_generator).to receive(:generate).ordered
        expect(mock_spectrogram_analyzer).to receive(:analyze).ordered
        expect(mock_text_analyzer).to receive(:analyze).ordered
        expect(mock_llm_converter).to receive(:convert_text_with_analysis).ordered

        converter.convert_with_audio_analysis(test_text, test_audio_file)
      end
    end

    context 'with invalid inputs' do
      it 'validates both text and audio inputs' do
        expect do
          converter.convert_with_audio_analysis('', test_audio_file)
        end.to raise_error(ArgumentError, /Text input cannot be nil or empty/)

        allow(File).to receive(:exist?).with('/bad.wav').and_return(false)
        expect do
          converter.convert_with_audio_analysis(test_text, '/bad.wav')
        end.to raise_error(ArgumentError, /Audio file not found/)
      end
    end
  end

  describe '.available_pitch_backends' do
    it 'delegates to PitchAnalyzerFactory' do
      expect(ProsodicTextConverter::PitchAnalyzerFactory).to receive(:available_backends)
        .and_return(%i[aubio sonic_annotator])

      result = described_class.available_pitch_backends
      expect(result).to eq(%i[aubio sonic_annotator])
    end
  end

  describe '.predefined_patterns' do
    it 'returns predefined prosodic patterns' do
      patterns = described_class.predefined_patterns

      expect(patterns).to have_key(:deliberate)
      expect(patterns).to have_key(:rapid)
      expect(patterns).to have_key(:contemplative)

      expect(patterns[:deliberate]).to be_a(ProsodicTextConverter::ProsodicPattern)
      expect(patterns[:deliberate].name).to eq('deliberate')
    end
  end

  describe 'private validation methods' do
    let(:converter) { described_class.new(logger: mock_logger) }

    describe '#validate_output_directory' do
      it 'creates directory if it does not exist' do
        allow(Dir).to receive(:exist?).with(test_output_dir).and_return(false)
        expect(FileUtils).to receive(:mkdir_p).with(test_output_dir)

        converter.send(:validate_output_directory, test_output_dir)
      end

      it 'raises error if directory cannot be created' do
        allow(Dir).to receive(:exist?).and_return(false)
        allow(FileUtils).to receive(:mkdir_p).and_raise(StandardError, 'Permission denied')

        expect do
          converter.send(:validate_output_directory, test_output_dir)
        end.to raise_error(ArgumentError, /Cannot create output directory/)
      end

      it 'raises error if directory is not writable' do
        allow(File).to receive(:writable?).with(test_output_dir).and_return(false)

        expect do
          converter.send(:validate_output_directory, test_output_dir)
        end.to raise_error(ArgumentError, /Output directory not writable/)
      end
    end
  end

  describe 'error handling and logging' do
    let(:converter) { described_class.new(logger: mock_logger) }

    it 'logs important steps during conversion' do
      allow(mock_text_analyzer).to receive(:analyze).and_return(text_analysis)
      allow(mock_llm_converter).to receive(:convert_text_with_analysis).and_return(ssml_output)
      allow(mock_ssml_formatter).to receive(:clean_ssml).and_return(validated_ssml)
      allow(mock_ssml_formatter).to receive(:extract_timing_info).and_return(timing_info)

      expect(mock_logger).to receive(:info).with(/Converting text \(\d+ chars\)/)
      expect(mock_logger).to receive(:info).with(/Text conversion completed in/)

      converter.convert(test_text)
    end

    it 'logs errors with backtraces for debugging' do
      allow(mock_text_analyzer).to receive(:analyze)
        .and_raise(StandardError, 'Test error')

      expect(mock_logger).to receive(:error).with(/Text conversion failed/)
      expect(mock_logger).to receive(:debug).with(/Backtrace:/)

      expect { converter.convert(test_text) }.to raise_error(RuntimeError)
    end
  end
end
