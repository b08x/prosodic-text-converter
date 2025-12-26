# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ProsodicTextConverter::LLMConverter do
  let(:test_text) { 'Hello world. This is a test sentence.' }
  let(:test_chunks) { ['Hello world.', 'This is a test sentence.'] }
  let(:mock_logger) { instance_double(Logger) }
  let(:mock_pattern) { instance_double(ProsodicTextConverter::ProsodicPattern) }
  let(:mock_client) { instance_double('RubyLLM::Client') }
  let(:mock_ruby_llm) { class_double('RubyLLM') }

  let(:text_analysis) do
    {
      original_text: test_text,
      language: 'en',
      sentence_count: 2,
      sentences: [
        {
          index: 0,
          text: 'Hello world.',
          word_count: 2,
          words: [
            { text: 'Hello', syllable_count: 2 },
            { text: 'world', syllable_count: 1 }
          ],
          pause_indicators: ['.']
        },
        {
          index: 1,
          text: 'This is a test sentence.',
          word_count: 5,
          words: [
            { text: 'This', syllable_count: 1 },
            { text: 'is', syllable_count: 1 },
            { text: 'a', syllable_count: 1 },
            { text: 'test', syllable_count: 1 },
            { text: 'sentence', syllable_count: 2 }
          ],
          pause_indicators: ['.']
        }
      ]
    }
  end

  let(:expected_ssml) do
    <<~SSML.strip
      <speak>
      <prosody rate="medium" pitch="+2%">Hello world.</prosody>
      <break time="350ms"/>
      <prosody rate="medium" pitch="-1%">This is a test sentence.</prosody>
      </speak>
    SSML
  end

  before do
    # Mock logger methods
    allow(mock_logger).to receive(:info)
    allow(mock_logger).to receive(:debug)
    allow(mock_logger).to receive(:error)
    allow(mock_logger).to receive(:warn)

    # Mock pattern methods
    allow(mock_pattern).to receive(:segment_duration).and_return(1.0)
    allow(mock_pattern).to receive(:pause_duration).and_return(0.35)
    allow(mock_pattern).to receive(:pitch_variation).and_return(5)
    allow(mock_pattern).to receive(:rate).and_return('medium')
    allow(mock_pattern).to receive(:respond_to?).with(:segment_duration).and_return(true)
    allow(mock_pattern).to receive(:respond_to?).with(:pause_duration).and_return(true)

    # Mock RubyLLM configuration and client
    stub_const('RubyLLM', mock_ruby_llm)
    allow(mock_ruby_llm).to receive(:configure).and_yield(double)
    allow(mock_ruby_llm).to receive(:chat).and_return(mock_client)

    # Mock client methods for new interface
    client_with_model = instance_double('RubyLLM::ClientWithModel')
    client_with_temp = instance_double('RubyLLM::ClientWithTemp')

    allow(mock_client).to receive(:with_model).and_return(client_with_model)
    allow(client_with_model).to receive(:with_temperature).and_return(client_with_temp)
    allow(client_with_temp).to receive(:ask).and_return(expected_ssml)

    # Mock client methods for legacy interface
    allow(mock_client).to receive(:chat).and_return(double(dig: expected_ssml, to_s: expected_ssml))

    # Mock RubyLLM::Message for response handling
    mock_message = instance_double('RubyLLM::Message')
    allow(mock_message).to receive(:content).and_return(expected_ssml)
    allow(mock_message).to receive(:to_s).and_return(expected_ssml)
    stub_const('RubyLLM::Message', Class.new)
  end

  describe '#initialize' do
    context 'with valid parameters' do
      it 'initializes successfully with default parameters' do
        converter = described_class.new(logger: mock_logger)

        expect(converter.provider).to eq(:gemini)
        expect(converter.model).to eq('gemini-2.5-flash')
        expect(converter.logger).to eq(mock_logger)
      end

      it 'initializes with custom parameters' do
        converter = described_class.new(
          provider: :openai,
          model: 'gpt-4',
          logger: mock_logger,
          temperature: 0.5
        )

        expect(converter.provider).to eq(:openai)
        expect(converter.model).to eq('gpt-4')
      end

      it 'validates configuration during initialization' do
        expect(mock_ruby_llm).to receive(:chat).with(provider: :gemini)

        described_class.new(logger: mock_logger)
      end
    end

    context 'with invalid parameters' do
      it 'raises error for invalid provider' do
        expect do
          described_class.new(provider: nil, logger: mock_logger)
        end.to raise_error(ArgumentError, /Provider must be a non-empty symbol/)
      end

      it 'raises error for invalid model' do
        expect do
          described_class.new(model: '', logger: mock_logger)
        end.to raise_error(ArgumentError, /Model must be a non-empty string/)
      end

      it 'raises error for empty provider symbol' do
        expect do
          described_class.new(provider: :"", logger: mock_logger)
        end.to raise_error(ArgumentError, /Provider must be a non-empty symbol/)
      end
    end

    context 'when LLM client initialization fails' do
      it 'raises error with context' do
        allow(mock_ruby_llm).to receive(:chat).and_raise(StandardError, 'API key invalid')

        expect do
          described_class.new(logger: mock_logger)
        end.to raise_error(RuntimeError, /Failed to initialize LLM converter.*API key invalid/)
      end
    end

    context 'when initialization times out' do
      it 'raises timeout error' do
        allow(mock_ruby_llm).to receive(:chat) do
          sleep(0.1)
          raise Timeout::Error
        end

        expect do
          described_class.new(logger: mock_logger)
        end.to raise_error(RuntimeError, /Timeout initializing LLM client/)
      end
    end
  end

  describe '#convert_text_with_analysis' do
    let(:converter) { described_class.new(logger: mock_logger) }

    context 'with valid inputs' do
      it 'successfully converts text using structured analysis' do
        result = converter.convert_text_with_analysis(text_analysis, mock_pattern)

        expect(result).to eq(expected_ssml)
      end

      it 'calls LLM with proper prompts' do
        client_with_model = instance_double('RubyLLM::ClientWithModel')
        client_with_temp = instance_double('RubyLLM::ClientWithTemp')

        expect(mock_client).to receive(:with_model).with('gemini-2.5-flash').and_return(client_with_model)
        expect(client_with_model).to receive(:with_temperature).with(0.3).and_return(client_with_temp)
        expect(client_with_temp).to receive(:ask).with(String).and_return(expected_ssml)

        converter.convert_text_with_analysis(text_analysis, mock_pattern)
      end

      it 'includes linguistic analysis in prompts' do
        client_with_model = instance_double('RubyLLM::ClientWithModel')
        client_with_temp = instance_double('RubyLLM::ClientWithTemp')

        allow(mock_client).to receive(:with_model).and_return(client_with_model)
        allow(client_with_model).to receive(:with_temperature).and_return(client_with_temp)

        expect(client_with_temp).to receive(:ask) do |prompt|
          expect(prompt).to include('LINGUISTIC ANALYSIS')
          expect(prompt).to include('Total sentences: 2')
          expect(prompt).to include('syllables')
          expected_ssml
        end

        converter.convert_text_with_analysis(text_analysis, mock_pattern)
      end

      it 'logs conversion progress' do
        expect(mock_logger).to receive(:info).with(/Converting text to SSML.*2 sentences/)
        expect(mock_logger).to receive(:info).with(/LLM conversion completed/)

        converter.convert_text_with_analysis(text_analysis, mock_pattern)
      end
    end

    context 'with invalid inputs' do
      it 'raises error for invalid text analysis' do
        expect do
          converter.convert_text_with_analysis({}, mock_pattern)
        end.to raise_error(ArgumentError, /Text analysis must be a hash with :original_text key/)
      end

      it 'raises error for missing sentences array' do
        invalid_analysis = text_analysis.dup
        invalid_analysis[:sentences] = []

        expect do
          converter.convert_text_with_analysis(invalid_analysis, mock_pattern)
        end.to raise_error(ArgumentError, /Text analysis must contain non-empty sentences array/)
      end

      it 'raises error for invalid pattern' do
        invalid_pattern = double
        allow(invalid_pattern).to receive(:respond_to?).and_return(false)

        expect do
          converter.convert_text_with_analysis(text_analysis, invalid_pattern)
        end.to raise_error(ArgumentError, /Pattern must respond to segment_duration and pause_duration/)
      end

      it 'raises error for empty original text' do
        invalid_analysis = text_analysis.dup
        invalid_analysis[:original_text] = ''

        expect do
          converter.convert_text_with_analysis(invalid_analysis, mock_pattern)
        end.to raise_error(ArgumentError, /Original text in analysis cannot be nil or empty/)
      end
    end

    context 'when LLM request fails' do
      it 'retries on failure and eventually succeeds' do
        client_with_model = instance_double('RubyLLM::ClientWithModel')
        client_with_temp = instance_double('RubyLLM::ClientWithTemp')

        allow(mock_client).to receive(:with_model).and_return(client_with_model)
        allow(client_with_model).to receive(:with_temperature).and_return(client_with_temp)

        # First call fails, second succeeds
        expect(client_with_temp).to receive(:ask)
          .and_raise(StandardError, 'API error')
          .ordered
        expect(client_with_temp).to receive(:ask)
          .and_return(expected_ssml)
          .ordered

        expect(mock_logger).to receive(:warn).with(%r{LLM request attempt 1/3 failed})

        result = converter.convert_text_with_analysis(text_analysis, mock_pattern)
        expect(result).to eq(expected_ssml)
      end

      it 'raises error after all retries fail' do
        client_with_model = instance_double('RubyLLM::ClientWithModel')
        client_with_temp = instance_double('RubyLLM::ClientWithTemp')

        allow(mock_client).to receive(:with_model).and_return(client_with_model)
        allow(client_with_model).to receive(:with_temperature).and_return(client_with_temp)
        allow(client_with_temp).to receive(:ask).and_raise(StandardError, 'Persistent error')

        expect do
          converter.convert_text_with_analysis(text_analysis, mock_pattern)
        end.to raise_error(RuntimeError, /All 3 LLM request attempts failed/)
      end
    end

    context 'when request times out' do
      it 'raises timeout error' do
        client_with_model = instance_double('RubyLLM::ClientWithModel')
        client_with_temp = instance_double('RubyLLM::ClientWithTemp')

        allow(mock_client).to receive(:with_model).and_return(client_with_model)
        allow(client_with_model).to receive(:with_temperature).and_return(client_with_temp)
        allow(client_with_temp).to receive(:ask) do
          sleep(0.1)
          raise Timeout::Error
        end

        expect do
          converter.convert_text_with_analysis(text_analysis, mock_pattern)
        end.to raise_error(RuntimeError, /LLM conversion timed out after 90 seconds/)
      end
    end
  end

  describe '#convert_text (legacy interface)' do
    let(:converter) { described_class.new(logger: mock_logger) }

    context 'with valid inputs' do
      it 'successfully converts text using legacy interface' do
        expect(mock_client).to receive(:chat).with(
          model: 'gemini-2.5-flash',
          messages: array_including(
            hash_including(role: 'system'),
            hash_including(role: 'user')
          ),
          max_tokens: 2000,
          temperature: 0.3
        ).and_return(double(dig: expected_ssml, to_s: expected_ssml))

        result = converter.convert_text(test_text, mock_pattern, test_chunks)
        expect(result).to eq(expected_ssml)
      end

      it 'includes chunk information in prompts' do
        expect(mock_client).to receive(:chat) do |args|
          user_message = args[:messages].find { |m| m[:role] == 'user' }[:content]
          expect(user_message).to include('SUGGESTED CHUNKING')
          expect(user_message).to include(test_chunks.join(' | '))
          double(dig: expected_ssml, to_s: expected_ssml)
        end

        converter.convert_text(test_text, mock_pattern, test_chunks)
      end
    end

    context 'with invalid inputs' do
      it 'raises error for empty text' do
        expect do
          converter.convert_text('', mock_pattern, test_chunks)
        end.to raise_error(ArgumentError, /Text cannot be nil or empty/)
      end

      it 'raises error for empty chunks array' do
        expect do
          converter.convert_text(test_text, mock_pattern, [])
        end.to raise_error(ArgumentError, /Chunks must be a non-empty array/)
      end

      it 'raises error for invalid pattern' do
        invalid_pattern = double
        allow(invalid_pattern).to receive(:respond_to?).and_return(false)

        expect do
          converter.convert_text(test_text, invalid_pattern, test_chunks)
        end.to raise_error(ArgumentError, /Pattern must respond to segment_duration and pause_duration/)
      end
    end
  end

  describe '#extract_response_content' do
    let(:converter) { described_class.new(logger: mock_logger) }

    context 'with different response types' do
      it 'extracts content from string response' do
        result = converter.send(:extract_response_content, expected_ssml)
        expect(result).to eq(expected_ssml)
      end

      it 'extracts content from RubyLLM::Message' do
        mock_message = instance_double('RubyLLM::Message')
        allow(mock_message).to receive(:content).and_return(expected_ssml)
        allow(mock_message).to receive(:is_a?).with(RubyLLM::Message).and_return(true)

        result = converter.send(:extract_response_content, mock_message)
        expect(result).to eq(expected_ssml)
      end

      it 'extracts content from hash response' do
        hash_response = { 'content' => expected_ssml }
        result = converter.send(:extract_response_content, hash_response)
        expect(result).to eq(expected_ssml)
      end

      it 'extracts content from nested hash response' do
        nested_response = { 'message' => { 'content' => expected_ssml } }
        result = converter.send(:extract_response_content, nested_response)
        expect(result).to eq(expected_ssml)
      end
    end

    context 'with markdown formatted content' do
      it 'removes markdown code blocks' do
        markdown_content = "```xml\n#{expected_ssml}\n```"
        result = converter.send(:extract_response_content, markdown_content)
        expect(result).to eq(expected_ssml)
      end

      it 'removes SSML-specific code blocks' do
        ssml_markdown = "```ssml\n#{expected_ssml}\n```"
        result = converter.send(:extract_response_content, ssml_markdown)
        expect(result).to eq(expected_ssml)
      end
    end

    context 'with invalid responses' do
      it 'raises error for empty content' do
        expect do
          converter.send(:extract_response_content, '')
        end.to raise_error(RuntimeError, /No content found in LLM response/)
      end

      it 'raises error for nil content' do
        expect do
          converter.send(:extract_response_content, nil)
        end.to raise_error(RuntimeError, /No content found in LLM response/)
      end
    end
  end

  describe 'retry mechanism' do
    let(:converter) { described_class.new(logger: mock_logger) }

    describe '#with_retries' do
      it 'succeeds on first attempt' do
        result = converter.send(:with_retries, max_attempts: 3) { 'success' }
        expect(result).to eq('success')
      end

      it 'retries and eventually succeeds' do
        attempt_count = 0
        result = converter.send(:with_retries, max_attempts: 3) do
          attempt_count += 1
          raise StandardError, 'Error' if attempt_count < 3

          'success'
        end

        expect(result).to eq('success')
        expect(attempt_count).to eq(3)
      end

      it 'fails after max attempts' do
        expect do
          converter.send(:with_retries, max_attempts: 2) do
            raise StandardError, 'Persistent error'
          end
        end.to raise_error(RuntimeError, /All 2 LLM request attempts failed/)
      end

      it 'uses exponential backoff between retries' do
        times = []
        expect do
          converter.send(:with_retries, max_attempts: 3) do
            times << Time.now
            raise StandardError, 'Error'
          end
        end.to raise_error(RuntimeError)

        # Should have made 3 attempts
        expect(times.length).to eq(3)

        # Check that there were delays between attempts (allowing for test timing variations)
        if times.length >= 2
          first_delay = times[1] - times[0]
          expect(first_delay).to be >= 1.8 # Should be ~2 seconds with some tolerance
        end
      end
    end
  end

  describe 'prompt building methods' do
    let(:converter) { described_class.new(logger: mock_logger) }

    describe '#build_system_prompt' do
      it 'returns comprehensive system prompt' do
        prompt = converter.send(:build_system_prompt)

        expect(prompt).to include('speech synthesis')
        expect(prompt).to include('SSML')
        expect(prompt).to include('prosodic patterns')
      end
    end

    describe '#build_analysis_conversion_prompt' do
      it 'includes linguistic analysis details' do
        prompt = converter.send(:build_analysis_conversion_prompt, text_analysis, mock_pattern)

        expect(prompt).to include('LINGUISTIC ANALYSIS')
        expect(prompt).to include('Total sentences: 2')
        expect(prompt).to include('syllables')
        expect(prompt).to include('Sentence 1: 2 words')
        expect(prompt).to include('Sentence 2: 5 words')
      end

      it 'includes pattern specifications' do
        prompt = converter.send(:build_analysis_conversion_prompt, text_analysis, mock_pattern)

        expect(prompt).to include('Segment duration: 1.0s')
        expect(prompt).to include('Pause duration: 350ms')
        expect(prompt).to include('Pitch variation: ±5%')
        expect(prompt).to include('Speaking rate: medium')
      end
    end

    describe '#optimal_words_per_chunk' do
      it 'calculates words per chunk based on pattern' do
        # medium rate (150 wpm) * 1.0s segment = 2.5 words, rounded to 3
        result = converter.send(:optimal_words_per_chunk, mock_pattern)
        expect(result).to eq(3)
      end

      it 'handles different speaking rates' do
        allow(mock_pattern).to receive(:rate).and_return('fast')
        allow(mock_pattern).to receive(:segment_duration).and_return(2.0)

        # fast rate (180 wpm) * 2.0s segment = 6 words
        result = converter.send(:optimal_words_per_chunk, mock_pattern)
        expect(result).to eq(6)
      end
    end
  end

  describe 'ElevenLabs phoneme support' do
    let(:mock_config) { instance_double('ProsodicTextConverter::Config') }
    let(:converter_with_config) { described_class.new(logger: mock_logger, config: mock_config) }

    context 'when phonemes are enabled and model supports them' do
      let(:models_config) do
        { 'eleven_turbo_v2' => { 'supports_phonemes' => true } }
      end

      before do
        allow(mock_config).to receive(:get).with(:elevenlabs_use_phonemes).and_return(true)
        allow(mock_config).to receive(:get).with(:elevenlabs_model_id).and_return('eleven_turbo_v2')
        allow(mock_config).to receive(:get).with(:elevenlabs_model).and_return(nil)
        allow(mock_config).to receive(:get).with('elevenlabs_models_config', {}).and_return(models_config)
      end

      it 'detects phoneme feature is enabled' do
        expect(converter_with_config.send(:elevenlabs_phonemes_enabled?)).to be true
      end

      it 'uses phoneme-specific prompts for conversion' do
        client_with_model = instance_double('RubyLLM::ClientWithModel')
        client_with_temp = instance_double('RubyLLM::ClientWithTemp')

        allow(mock_client).to receive(:with_model).and_return(client_with_model)
        allow(client_with_model).to receive(:with_temperature).and_return(client_with_temp)

        expect(client_with_temp).to receive(:ask) do |prompt|
          expect(prompt).to include('phoneme tags for precise pronunciation')
          expect(prompt).to include('<phoneme alphabet="ipa"')
          expect(prompt).to include('PHONEME TAG GUIDANCE')
          expect(prompt).to include('Kubernetes')
          expected_ssml
        end

        converter_with_config.convert_text_with_analysis(text_analysis, mock_pattern)
      end
    end

    context 'when phonemes are enabled but model does not support them' do
      let(:models_config) do
        { 'eleven_basic_v1' => { 'supports_phonemes' => false } }
      end

      before do
        allow(mock_config).to receive(:get).with(:elevenlabs_use_phonemes).and_return(true)
        allow(mock_config).to receive(:get).with(:elevenlabs_model_id).and_return('eleven_basic_v1')
        allow(mock_config).to receive(:get).with(:elevenlabs_model).and_return(nil)
        allow(mock_config).to receive(:get).with('elevenlabs_models_config', {}).and_return(models_config)
      end

      it 'detects phoneme feature is disabled due to model incompatibility' do
        expect(converter_with_config.send(:elevenlabs_phonemes_enabled?)).to be false
      end

      it 'uses standard prompts for conversion' do
        client_with_model = instance_double('RubyLLM::ClientWithModel')
        client_with_temp = instance_double('RubyLLM::ClientWithTemp')

        allow(mock_client).to receive(:with_model).and_return(client_with_model)
        allow(client_with_model).to receive(:with_temperature).and_return(client_with_temp)

        expect(client_with_temp).to receive(:ask) do |prompt|
          expect(prompt).not_to include('phoneme tags for precise pronunciation')
          expect(prompt).not_to include('PHONEME TAG GUIDANCE')
          expected_ssml
        end

        converter_with_config.convert_text_with_analysis(text_analysis, mock_pattern)
      end
    end

    context 'when phonemes are disabled' do
      before do
        allow(mock_config).to receive(:get).with(:elevenlabs_use_phonemes).and_return(false)
        allow(mock_config).to receive(:get).with(:elevenlabs_model_id).and_return('eleven_turbo_v2')
        allow(mock_config).to receive(:get).with(:elevenlabs_model).and_return(nil)
      end

      it 'detects phoneme feature is disabled' do
        expect(converter_with_config.send(:elevenlabs_phonemes_enabled?)).to be false
      end
    end
  end

  describe 'ElevenLabs v3 model support' do
    let(:mock_config) { instance_double('ProsodicTextConverter::Config') }
    let(:converter_with_config) { described_class.new(logger: mock_logger, config: mock_config) }

    context 'when ElevenLabs v3 model is configured' do
      before do
        allow(mock_config).to receive(:get).with(:elevenlabs_model_id).and_return('eleven_turbo_v3')
      end

      it 'detects v3 model correctly' do
        expect(converter_with_config.send(:elevenlabs_v3_model?)).to be true
      end

      it 'uses v3-specific prompts for conversion' do
        client_with_model = instance_double('RubyLLM::ClientWithModel')
        client_with_temp = instance_double('RubyLLM::ClientWithTemp')

        allow(mock_client).to receive(:with_model).and_return(client_with_model)
        allow(client_with_model).to receive(:with_temperature).and_return(client_with_temp)

        expect(client_with_temp).to receive(:ask) do |prompt|
          expect(prompt).to include('ElevenLabs v3 models')
          expect(prompt).to include('[laughs]')
          expect(prompt).to include('[sighs]')
          expect(prompt).to include('ELEVENLABS V3 AUDIO TAG GUIDANCE')
          expected_ssml
        end

        converter_with_config.convert_text_with_analysis(text_analysis, mock_pattern)
      end

      it 'includes audio tag examples in v3 prompts' do
        client_with_model = instance_double('RubyLLM::ClientWithModel')
        client_with_temp = instance_double('RubyLLM::ClientWithTemp')

        allow(mock_client).to receive(:with_model).and_return(client_with_model)
        allow(client_with_model).to receive(:with_temperature).and_return(client_with_temp)

        expect(client_with_temp).to receive(:ask) do |prompt|
          expect(prompt).to include('[excited] absolutely fantastic!')
          expect(prompt).to include('[sarcastic] That\'s very interesting.')
          expected_ssml
        end

        converter_with_config.convert_text_with_analysis(text_analysis, mock_pattern)
      end
    end

    context 'when ElevenLabs v3 model is not configured' do
      before do
        allow(mock_config).to receive(:get).with(:elevenlabs_model_id).and_return('eleven_turbo_v2')
        allow(mock_config).to receive(:get).with(:elevenlabs_use_phonemes).and_return(false)
      end

      it 'detects non-v3 model correctly' do
        expect(converter_with_config.send(:elevenlabs_v3_model?)).to be false
      end

      it 'uses standard prompts for conversion' do
        client_with_model = instance_double('RubyLLM::ClientWithModel')
        client_with_temp = instance_double('RubyLLM::ClientWithTemp')

        allow(mock_client).to receive(:with_model).and_return(client_with_model)
        allow(client_with_model).to receive(:with_temperature).and_return(client_with_temp)

        expect(client_with_temp).to receive(:ask) do |prompt|
          expect(prompt).not_to include('ElevenLabs v3 models')
          expect(prompt).not_to include('[laughs]')
          expect(prompt).not_to include('ELEVENLABS V3 AUDIO TAG GUIDANCE')
          expected_ssml
        end

        converter_with_config.convert_text_with_analysis(text_analysis, mock_pattern)
      end
    end

    context 'when no config is provided' do
      it 'defaults to standard prompts' do
        converter_without_config = described_class.new(logger: mock_logger)
        expect(converter_without_config.send(:elevenlabs_v3_model?)).to be false
      end
    end
  end

  describe 'error handling and logging' do
    let(:converter) { described_class.new(logger: mock_logger) }

    it 'logs detailed conversion information' do
      client_with_model = instance_double('RubyLLM::ClientWithModel')
      client_with_temp = instance_double('RubyLLM::ClientWithTemp')

      allow(mock_client).to receive(:with_model).and_return(client_with_model)
      allow(client_with_model).to receive(:with_temperature).and_return(client_with_temp)
      allow(client_with_temp).to receive(:ask).and_return(expected_ssml)

      expect(mock_logger).to receive(:info).with(/Converting text to SSML/)
      expect(mock_logger).to receive(:debug).with(/Sending request to gemini:gemini-2.5-flash/)
      expect(mock_logger).to receive(:info).with(/LLM conversion completed/)
      expect(mock_logger).to receive(:debug).with(/Generated SSML length:/)

      converter.convert_text_with_analysis(text_analysis, mock_pattern)
    end

    it 'logs errors with detailed context' do
      client_with_model = instance_double('RubyLLM::ClientWithModel')
      client_with_temp = instance_double('RubyLLM::ClientWithTemp')

      allow(mock_client).to receive(:with_model).and_return(client_with_model)
      allow(client_with_model).to receive(:with_temperature).and_return(client_with_temp)
      allow(client_with_temp).to receive(:ask).and_raise(StandardError, 'API error')

      expect(mock_logger).to receive(:error).with(/All 3 LLM request attempts failed/)

      expect do
        converter.convert_text_with_analysis(text_analysis, mock_pattern)
      end.to raise_error(RuntimeError)
    end
  end
end
