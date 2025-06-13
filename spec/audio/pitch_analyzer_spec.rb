# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ProsodicTextConverter::PitchAnalyzer do
  let(:test_audio_file) { '/path/to/test_audio.wav' }
  let(:mock_logger) { instance_double(Logger) }

  before do
    allow(mock_logger).to receive(:info)
    allow(mock_logger).to receive(:debug)
    allow(mock_logger).to receive(:error)
    allow(mock_logger).to receive(:warn)

    # Mock file system
    allow(File).to receive(:exist?).with(test_audio_file).and_return(true)
    allow(File).to receive(:readable?).with(test_audio_file).and_return(true)
  end

  describe '.new' do
    it 'is an abstract class that cannot be instantiated directly' do
      expect { described_class.new }.to raise_error(NoMethodError)
    end
  end

  describe '#validate_audio_file' do
    let(:analyzer) { ProsodicTextConverter::AubioPitchAnalyzer.new(logger: mock_logger) }

    context 'with valid audio file' do
      it 'passes validation' do
        expect { analyzer.send(:validate_audio_file, test_audio_file) }.not_to raise_error
      end
    end

    context 'with invalid audio file' do
      it 'raises error for nil path' do
        expect { analyzer.send(:validate_audio_file, nil) }
          .to raise_error(ArgumentError, /Audio file path cannot be nil or empty/)
      end

      it 'raises error for empty path' do
        expect { analyzer.send(:validate_audio_file, '   ') }
          .to raise_error(ArgumentError, /Audio file path cannot be nil or empty/)
      end

      it 'raises error for non-existent file' do
        allow(File).to receive(:exist?).with('/nonexistent.wav').and_return(false)

        expect { analyzer.send(:validate_audio_file, '/nonexistent.wav') }
          .to raise_error(ArgumentError, /Audio file not found/)
      end

      it 'raises error for unreadable file' do
        allow(File).to receive(:readable?).with(test_audio_file).and_return(false)

        expect { analyzer.send(:validate_audio_file, test_audio_file) }
          .to raise_error(ArgumentError, /Audio file not readable/)
      end
    end
  end

  describe '#calculate_pitch_variation' do
    let(:analyzer) { ProsodicTextConverter::AubioPitchAnalyzer.new(logger: mock_logger) }

    context 'with valid pitch data' do
      it 'calculates coefficient of variation correctly' do
        pitch_data = [
          { timestamp: 0.0, frequency: 100.0 },
          { timestamp: 0.1, frequency: 110.0 },
          { timestamp: 0.2, frequency: 90.0 },
          { timestamp: 0.3, frequency: 105.0 }
        ]

        result = analyzer.calculate_pitch_variation(pitch_data)

        expect(result).to be_a(Float)
        expect(result).to be_between(1.0, 15.0)
      end

      it 'filters out zero frequencies' do
        pitch_data = [
          { timestamp: 0.0, frequency: 100.0 },
          { timestamp: 0.1, frequency: 0.0 },
          { timestamp: 0.2, frequency: 110.0 }
        ]

        result = analyzer.calculate_pitch_variation(pitch_data)
        expect(result).to be > 0
      end

      it 'clamps result between 1.0 and 15.0' do
        # Data with very low variation
        low_variation_data = [
          { timestamp: 0.0, frequency: 100.0 },
          { timestamp: 0.1, frequency: 100.1 }
        ]

        result = analyzer.calculate_pitch_variation(low_variation_data)
        expect(result).to be >= 1.0

        # Data with very high variation would be clamped to 15.0
        # (though hard to construct realistic data that exceeds 15%)
      end
    end

    context 'with edge cases' do
      it 'returns default value for empty data' do
        result = analyzer.calculate_pitch_variation([])
        expect(result).to eq(5.0)
      end

      it 'returns default value for insufficient data' do
        pitch_data = [{ timestamp: 0.0, frequency: 100.0 }]
        result = analyzer.calculate_pitch_variation(pitch_data)
        expect(result).to eq(5.0)
      end

      it 'handles calculation errors gracefully' do
        # Mock a calculation error
        allow(analyzer).to receive(:calculate_pitch_variation).and_call_original
        pitch_data = [
          { timestamp: 0.0, frequency: 100.0 },
          { timestamp: 0.1, frequency: 110.0 }
        ]

        # Stub one of the internal calculations to raise an error
        allow(pitch_data).to receive(:map).and_raise(StandardError, 'Calculation error')

        result = analyzer.calculate_pitch_variation(pitch_data)
        expect(result).to eq(5.0)
      end
    end
  end
end

RSpec.describe ProsodicTextConverter::AubioPitchAnalyzer do
  let(:test_audio_file) { '/path/to/test_audio.wav' }
  let(:mock_logger) { instance_double(Logger) }
  let(:mock_aubio_source) { instance_double('Aubio::Source') }
  let(:mock_aubio_pitch) { instance_double('Aubio::Pitch') }

  before do
    allow(mock_logger).to receive(:info)
    allow(mock_logger).to receive(:debug)
    allow(mock_logger).to receive(:error)
    allow(mock_logger).to receive(:warn)

    # Mock file system
    allow(File).to receive(:exist?).with(test_audio_file).and_return(true)
    allow(File).to receive(:readable?).with(test_audio_file).and_return(true)

    # Mock Aubio FFI calls (without requiring the actual gem)
    stub_const('Aubio::Source', Class.new)
    stub_const('Aubio::Pitch', Class.new)
    allow(Aubio::Source).to receive(:new).and_return(mock_aubio_source)
    allow(Aubio::Pitch).to receive(:new).and_return(mock_aubio_pitch)
  end

  describe '#initialize' do
    it 'initializes with default parameters' do
      analyzer = described_class.new(logger: mock_logger)

      expect(analyzer.algorithm).to eq('yin')
      expect(analyzer.hop_size).to eq(512)
      expect(analyzer.buffer_size).to eq(1024)
      expect(analyzer.sample_rate).to eq(44_100)
    end

    it 'initializes with custom parameters' do
      analyzer = described_class.new(
        algorithm: 'mcomb',
        hop_size: 256,
        buffer_size: 2048,
        sample_rate: 22_050,
        logger: mock_logger
      )

      expect(analyzer.algorithm).to eq('mcomb')
      expect(analyzer.hop_size).to eq(256)
      expect(analyzer.buffer_size).to eq(2048)
      expect(analyzer.sample_rate).to eq(22_050)
    end
  end

  describe '#analyze' do
    let(:analyzer) { described_class.new(logger: mock_logger) }

    let(:sample_audio_data) do
      # Mock some sample frames
      [
        [0.1, 0.2, 0.3],  # First frame
        [0.2, 0.1, 0.4],  # Second frame
        []                # End of stream
      ]
    end

    let(:pitch_frequencies) { [150.0, 160.0] } # Corresponding pitch values

    before do
      # Mock Aubio processing workflow
      allow(mock_aubio_source).to receive(:do_multi).and_return(true, true, false)
      allow(mock_aubio_source).to receive(:get_next_samples)
        .and_return(*sample_audio_data)

      allow(mock_aubio_pitch).to receive(:do)
        .and_return(*pitch_frequencies)
    end

    context 'with valid audio file' do
      it 'successfully analyzes audio and returns pitch data' do
        result = analyzer.analyze(test_audio_file)

        expect(result).to be_an(Array)
        expect(result.length).to eq(2)

        expect(result.first).to include(
          timestamp: be_a(Float),
          frequency: 150.0
        )

        expect(result.last).to include(
          timestamp: be_a(Float),
          frequency: 160.0
        )
      end

      it 'filters out frequencies outside speech range' do
        # Mock frequencies outside the 50-800 Hz range
        allow(mock_aubio_pitch).to receive(:do)
          .and_return(30.0, 900.0, 200.0) # Only 200.0 should be kept

        allow(mock_aubio_source).to receive(:do_multi).and_return(true, true, true, false)
        allow(mock_aubio_source).to receive(:get_next_samples)
          .and_return([0.1], [0.2], [0.3], [])

        result = analyzer.analyze(test_audio_file)

        expect(result.length).to eq(1)
        expect(result.first[:frequency]).to eq(200.0)
      end

      it 'calculates timestamps correctly based on frame position' do
        result = analyzer.analyze(test_audio_file)

        # First frame at timestamp 0
        expect(result.first[:timestamp]).to eq(0.0)

        # Second frame at timestamp = hop_size / sample_rate
        expected_second_timestamp = 512.0 / 44_100.0
        expect(result.last[:timestamp]).to be_within(0.001).of(expected_second_timestamp)
      end

      it 'logs analysis progress and results' do
        expect(mock_logger).to receive(:info).with(/Starting FFI Aubio pitch analysis/)
        expect(mock_logger).to receive(:info).with(/FFI Aubio analysis completed/)
        expect(mock_logger).to receive(:debug).with(/Frequency range:/)

        analyzer.analyze(test_audio_file)
      end
    end

    context 'when no valid pitch data is found' do
      it 'logs warning and returns empty array' do
        # Mock all frequencies outside valid range
        allow(mock_aubio_pitch).to receive(:do).and_return(30.0, 900.0)

        expect(mock_logger).to receive(:warn).with('No valid pitch data extracted from audio')

        result = analyzer.analyze(test_audio_file)
        expect(result).to be_empty
      end
    end

    context 'when FFI calls fail' do
      it 'raises error with context' do
        allow(Aubio::Source).to receive(:new).and_raise(StandardError, 'FFI error')

        expect { analyzer.analyze(test_audio_file) }
          .to raise_error(RuntimeError, /FFI Aubio analysis failed.*FFI error/)
      end
    end

    context 'with invalid audio file' do
      it 'validates file before processing' do
        allow(File).to receive(:exist?).with('/nonexistent.wav').and_return(false)

        expect { analyzer.analyze('/nonexistent.wav') }
          .to raise_error(ArgumentError, /Audio file not found/)
      end
    end
  end
end

RSpec.describe ProsodicTextConverter::SonicAnnotatorPitchAnalyzer do
  let(:test_audio_file) { '/path/to/test_audio.wav' }
  let(:transform_dir) { '/path/to/transforms' }
  let(:mock_logger) { instance_double(Logger) }

  before do
    allow(mock_logger).to receive(:info)
    allow(mock_logger).to receive(:debug)
    allow(mock_logger).to receive(:error)
    allow(mock_logger).to receive(:warn)

    # Mock file system operations
    allow(File).to receive(:exist?).with(test_audio_file).and_return(true)
    allow(File).to receive(:readable?).with(test_audio_file).and_return(true)
    allow(FileUtils).to receive(:mkdir_p)
    allow(File).to receive(:write)

    # Mock sonic-annotator availability
    allow(Open3).to receive(:capture3).with('which', 'sonic-annotator')
                                      .and_return(['', '', double(success?: true)])
    allow(Open3).to receive(:capture3).with('sonic-annotator', '-l')
                                      .and_return(["pyin:pyin\nvamp-example-plugins:fixedtempo", '',
                                                   double(success?: true)])
  end

  describe '#initialize' do
    it 'initializes with default parameters' do
      analyzer = described_class.new(logger: mock_logger)

      expect(analyzer.plugin).to eq('pyin:pyin:f0candidates')
      expect(analyzer.step_size).to eq(256)
      expect(analyzer.block_size).to eq(2048)
    end

    it 'creates transform directory and files' do
      expect(FileUtils).to receive(:mkdir_p).with(anything)
      expect(File).to receive(:write).at_least(4).times # 4 transform files

      described_class.new(logger: mock_logger)
    end

    it 'validates sonic-annotator availability' do
      expect(Open3).to receive(:capture3).with('which', 'sonic-annotator')
      expect(Open3).to receive(:capture3).with('sonic-annotator', '-l')

      described_class.new(logger: mock_logger)
    end

    context 'when sonic-annotator is not available' do
      it 'raises error' do
        allow(Open3).to receive(:capture3).with('which', 'sonic-annotator')
                                          .and_return(['', 'not found', double(success?: false)])

        expect { described_class.new(logger: mock_logger) }
          .to raise_error(RuntimeError, /Sonic Annotator not found/)
      end
    end

    context 'when required plugins are missing' do
      it 'logs warning but continues' do
        allow(Open3).to receive(:capture3).with('sonic-annotator', '-l')
                                          .and_return(['other-plugin', '', double(success?: true)])

        expect(mock_logger).to receive(:warn).with(/Missing Vamp plugins/)

        described_class.new(logger: mock_logger)
      end
    end
  end

  describe '#analyze' do
    let(:analyzer) { described_class.new(logger: mock_logger) }

    let(:rdf_pitch_output) do
      <<~RDF
        @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
        @prefix event: <http://example.org/event/> .

        event:1 <http://example.org/time> "0.0"^^xsd:float ;
                <http://example.org/value> "150.0"^^xsd:float .

        event:2 <http://example.org/time> "0.1"^^xsd:float ;
                <http://example.org/value> "160.0"^^xsd:float .
      RDF
    end

    let(:rdf_tempo_output) do
      <<~RDF
        @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
        @prefix event: <http://example.org/event/> .

        event:1 <http://example.org/time> "0.0"^^xsd:float ;
                <http://example.org/value> "120.0"^^xsd:float .
      RDF
    end

    before do
      # Mock RDF parsing
      stub_const('RDF::Graph', Class.new)
      stub_const('RDF::Turtle::Reader', Class.new)

      mock_graph = instance_double('RDF::Graph')
      allow(RDF::Graph).to receive(:new).and_return(mock_graph)
      allow(RDF::Turtle::Reader).to receive(:new).and_yield(double)
      allow(mock_graph).to receive(:<<)

      # Mock successful RDF parsing results
      allow(analyzer).to receive(:parse_rdf_output).and_return([
                                                                 { timestamp: 0.0, frequency: 150.0, confidence: 1.0 },
                                                                 { timestamp: 0.1, frequency: 160.0, confidence: 1.0 }
                                                               ])

      allow(analyzer).to receive(:parse_tempo_rdf_output).and_return([
                                                                       { timestamp: 0.0, tempo: 120.0 }
                                                                     ])
    end

    context 'with successful analysis' do
      before do
        # Mock successful sonic-annotator calls
        allow(Open3).to receive(:capture3).with(
          'sonic-annotator', '-q', '-t', anything, test_audio_file, '-w', 'rdf'
        ).and_return([rdf_pitch_output, '', double(success?: true)])
      end

      it 'successfully analyzes audio with RDF output' do
        result = analyzer.analyze(test_audio_file)

        expect(result).to be_an(Array)
        expect(result.length).to eq(2)

        expect(result.first).to include(
          timestamp: 0.0,
          frequency: 150.0,
          confidence: 1.0
        )
      end

      it 'includes tempo context when available' do
        result = analyzer.analyze(test_audio_file)

        # Should have tempo context added by combine_analysis_results
        expect(result.first).to have_key(:tempo_context)
      end

      it 'logs analysis progress' do
        expect(mock_logger).to receive(:info).with(/Starting Sonic Annotator RDF analysis/)
        expect(mock_logger).to receive(:info).with(/Sonic Annotator RDF analysis completed/)

        analyzer.analyze(test_audio_file)
      end
    end

    context 'when pitch analysis fails' do
      it 'raises error with sonic-annotator error message' do
        allow(Open3).to receive(:capture3).with(
          'sonic-annotator', '-q', '-t', anything, test_audio_file, '-w', 'rdf'
        ).and_return(['', 'Analysis failed', double(success?: false)])

        expect { analyzer.analyze(test_audio_file) }
          .to raise_error(RuntimeError, /Sonic Annotator analysis failed/)
      end
    end

    context 'when tempo analysis fails' do
      it 'continues with empty tempo data' do
        # Pitch succeeds, tempo fails
        allow(Open3).to receive(:capture3).with(
          'sonic-annotator', '-q', '-t', /pyin/, test_audio_file, '-w', 'rdf'
        ).and_return([rdf_pitch_output, '', double(success?: true)])

        allow(Open3).to receive(:capture3).with(
          'sonic-annotator', '-q', '-t', /tempo/, test_audio_file, '-w', 'rdf'
        ).and_return(['', 'Tempo failed', double(success?: false)])

        expect(mock_logger).to receive(:warn).with(/Tempo analysis failed \(optional\)/)

        result = analyzer.analyze(test_audio_file)
        expect(result).not_to be_empty # Should still have pitch data
      end
    end

    context 'when analysis times out' do
      it 'raises timeout error' do
        allow(analyzer).to receive(:extract_pitch_data_rdf) do
          sleep(0.1)
          raise Timeout::Error
        end

        expect { analyzer.analyze(test_audio_file) }
          .to raise_error(RuntimeError, /Sonic Annotator analysis timed out/)
      end
    end
  end

  describe 'RDF parsing methods' do
    let(:analyzer) { described_class.new(logger: mock_logger) }

    describe '#parse_rdf_output' do
      let(:rdf_output) do
        <<~RDF
          @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
          @prefix event: <http://example.org/event/> .

          event:1 <http://example.org/time> "0.0"^^xsd:float ;
                  <http://example.org/value> "150.0"^^xsd:float .

          event:2 <http://example.org/time> "0.1"^^xsd:float ;
                  <http://example.org/value> "30.0"^^xsd:float .

          event:3 <http://example.org/time> "0.2"^^xsd:float ;
                  <http://example.org/value> "900.0"^^xsd:float .
        RDF
      end

      before do
        # Mock RDF parsing infrastructure
        stub_const('RDF::Graph', Class.new)
        stub_const('RDF::Turtle::Reader', Class.new)

        mock_graph = instance_double('RDF::Graph')
        mock_reader = instance_double('RDF::Turtle::Reader')

        allow(RDF::Graph).to receive(:new).and_return(mock_graph)
        allow(RDF::Turtle::Reader).to receive(:new).with(rdf_output).and_yield(mock_reader)
        allow(mock_reader).to receive(:each_statement)
        allow(mock_graph).to receive(:<<)

        # Mock graph queries to return realistic results
        allow(mock_graph).to receive(:each_statement).and_yield(
          double(subject: 'event:1', predicate: double(to_s: 'time'), object: double(to_f: 0.0))
        ).and_yield(
          double(subject: 'event:1', predicate: double(to_s: 'value'), object: double(to_f: 150.0))
        )

        allow(mock_graph).to receive(:query).and_return([
                                                          double(predicate: double(to_s: 'time'),
                                                                 object: double(to_f: 0.0)),
                                                          double(predicate: double(to_s: 'value'),
                                                                 object: double(to_f: 150.0))
                                                        ])
      end

      # NOTE: Full RDF parsing is complex to mock completely, so we test the error handling
      it 'handles RDF parsing errors gracefully' do
        allow(RDF::Graph).to receive(:new).and_raise(StandardError, 'RDF parse error')

        expect(mock_logger).to receive(:error).with(/Error parsing RDF output/)

        result = analyzer.send(:parse_rdf_output, rdf_output)
        expect(result).to eq([])
      end
    end
  end
end

RSpec.describe ProsodicTextConverter::PitchAnalyzerFactory do
  describe '.create' do
    let(:mock_logger) { instance_double(Logger) }

    before do
      allow(mock_logger).to receive(:info)
      allow(mock_logger).to receive(:debug)
      allow(mock_logger).to receive(:error)

      # Mock Aubio availability
      stub_const('Aubio::Source', Class.new)
      stub_const('Aubio::Pitch', Class.new)

      # Mock Sonic Annotator availability
      allow(Open3).to receive(:capture3).with('which', 'sonic-annotator')
                                        .and_return(['', '', double(success?: true)])
      allow(Open3).to receive(:capture3).with('sonic-annotator', '-l')
                                        .and_return(['pyin:pyin', '', double(success?: true)])
      allow(FileUtils).to receive(:mkdir_p)
      allow(File).to receive(:write)
    end

    it 'creates Aubio analyzer' do
      analyzer = described_class.create(backend: :aubio, logger: mock_logger)
      expect(analyzer).to be_a(ProsodicTextConverter::AubioPitchAnalyzer)
    end

    it 'creates Sonic Annotator analyzer' do
      analyzer = described_class.create(backend: :sonic_annotator, logger: mock_logger)
      expect(analyzer).to be_a(ProsodicTextConverter::SonicAnnotatorPitchAnalyzer)
    end

    it 'passes options to analyzer constructor' do
      expect(ProsodicTextConverter::AubioPitchAnalyzer).to receive(:new)
        .with(algorithm: 'mcomb', hop_size: 256, logger: mock_logger)

      described_class.create(
        backend: :aubio,
        algorithm: 'mcomb',
        hop_size: 256,
        logger: mock_logger
      )
    end

    it 'raises error for unknown backend' do
      expect { described_class.create(backend: :unknown) }
        .to raise_error(ArgumentError, /Unknown pitch analyzer backend: unknown/)
    end
  end

  describe '.available_backends' do
    context 'when both backends are available' do
      before do
        # Mock Aubio availability
        stub_const('Aubio', Module.new)

        # Mock Sonic Annotator availability
        allow(Kernel).to receive(:system).with('which sonic-annotator > /dev/null 2>&1')
                                         .and_return(true)
      end

      it 'returns both backends' do
        backends = described_class.available_backends
        expect(backends).to include(:aubio, :sonic_annotator)
      end
    end

    context 'when only Aubio is available' do
      before do
        stub_const('Aubio', Module.new)
        allow(Kernel).to receive(:system).and_return(false)
      end

      it 'returns only aubio' do
        backends = described_class.available_backends
        expect(backends).to eq([:aubio])
      end
    end

    context 'when no backends are available' do
      before do
        # Aubio gem not available
        allow(described_class).to receive(:require).with('aubio')
                                                   .and_raise(LoadError)

        # Sonic Annotator not installed
        allow(Kernel).to receive(:system).and_return(false)
      end

      it 'returns empty array' do
        backends = described_class.available_backends
        expect(backends).to eq([])
      end
    end
  end
end
