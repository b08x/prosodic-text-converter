# frozen_string_literal: true

require 'spec_helper'
require_relative '../lib/prosodic-text-converter/conversion/elevenlabs_formatter'

RSpec.describe ProsodicTextConverter::ElevenLabsFormatter do
  let(:formatter) { described_class.new }

  describe '#convert_to_elevenlabs_format' do
    context 'with break tags' do
      it 'caps break times at 3 seconds' do
        ssml = '<speak><break time="5000ms"/>Hello world</speak>'
        result = formatter.convert_to_elevenlabs_format(ssml)

        expect(result).to include('time="3.0s"')
        expect(result).not_to include('5000ms')
      end

      it 'converts milliseconds to seconds' do
        ssml = '<speak><break time="500ms"/>Hello world</speak>'
        result = formatter.convert_to_elevenlabs_format(ssml)

        expect(result).to include('time="0.5s"')
      end

      it 'preserves break times under the limit' do
        ssml = '<speak><break time="1.5s"/>Hello world</speak>'
        result = formatter.convert_to_elevenlabs_format(ssml)

        expect(result).to include('time="1.5s"')
      end
    end

    context 'with prosody tags' do
      it 'normalizes extreme rate values' do
        ssml = '<speak><prosody rate="x-slow">Hello</prosody></speak>'
        result = formatter.convert_to_elevenlabs_format(ssml)

        expect(result).to include('rate="slow"')
      end

      it 'clamps pitch percentages' do
        ssml = '<speak><prosody pitch="+100%">Hello</prosody></speak>'
        result = formatter.convert_to_elevenlabs_format(ssml)

        expect(result).to include('pitch="+50%"')
      end

      it 'handles negative pitch values' do
        ssml = '<speak><prosody pitch="-80%">Hello</prosody></speak>'
        result = formatter.convert_to_elevenlabs_format(ssml)

        expect(result).to include('pitch="-50%"')
      end
    end

    context 'with phoneme tags' do
      it 'removes phoneme tags for unsupported models' do
        ssml = '<speak><phoneme alphabet="ipa" ph="həˈloʊ">hello</phoneme></speak>'
        result = formatter.convert_to_elevenlabs_format(ssml, model_id: 'unsupported_model')

        expect(result).to include('hello')
        expect(result).not_to include('<phoneme')
      end

      it 'preserves phoneme tags for supported models' do
        ssml = '<speak><phoneme alphabet="ipa" ph="həˈloʊ">hello</phoneme></speak>'
        result = formatter.convert_to_elevenlabs_format(ssml, model_id: 'eleven_english_v1')

        expect(result).to include('<phoneme')
        expect(result).to include('alphabet="ipa"')
      end
    end

    context 'with complex SSML' do
      it 'handles multiple elements correctly' do
        ssml = <<~SSML
          <speak>
            <prosody rate="medium" pitch="+2%">First segment</prosody>
            <break time="2500ms"/>
            <prosody rate="fast" pitch="-1%">Second segment</prosody>
          </speak>
        SSML

        result = formatter.convert_to_elevenlabs_format(ssml)

        expect(result).to include('time="2.5s"')
        expect(result).to include('pitch="+2.0%"')
        expect(result).to include('pitch="-1.0%"')
        expect(result).to include('rate="medium"')
        expect(result).to include('rate="fast"')
      end
    end
  end

  describe '#model_supports_phonemes?' do
    it 'returns true for supported models' do
      expect(formatter.send(:model_supports_phonemes?, 'eleven_english_v1')).to be true
      expect(formatter.send(:model_supports_phonemes?, 'eleven_flash_v2')).to be true
      expect(formatter.send(:model_supports_phonemes?, 'eleven_turbo_v2')).to be true
    end

    it 'returns false for unsupported models' do
      expect(formatter.send(:model_supports_phonemes?, 'eleven_monolingual_v1')).to be false
      expect(formatter.send(:model_supports_phonemes?, 'unknown_model')).to be false
    end
  end

  describe '#convert_to_seconds' do
    it 'converts milliseconds correctly' do
      expect(formatter.send(:convert_to_seconds, '500ms')).to eq(0.5)
      expect(formatter.send(:convert_to_seconds, '1500ms')).to eq(1.5)
    end

    it 'handles seconds correctly' do
      expect(formatter.send(:convert_to_seconds, '2.5s')).to eq(2.5)
      expect(formatter.send(:convert_to_seconds, '1s')).to eq(1.0)
    end

    it 'assumes milliseconds for unitless values' do
      expect(formatter.send(:convert_to_seconds, '1000')).to eq(1.0)
    end
  end

  describe '#normalize_pitch_value' do
    it 'clamps positive percentages' do
      expect(formatter.send(:normalize_pitch_value, '+80%')).to eq('+50%')
      expect(formatter.send(:normalize_pitch_value, '+30%')).to eq('+30.0%')
    end

    it 'clamps negative percentages' do
      expect(formatter.send(:normalize_pitch_value, '-80%')).to eq('-50%')
      expect(formatter.send(:normalize_pitch_value, '-30%')).to eq('-30.0%')
    end

    it 'handles non-percentage values unchanged' do
      expect(formatter.send(:normalize_pitch_value, 'high')).to eq('high')
      expect(formatter.send(:normalize_pitch_value, 'low')).to eq('low')
    end
  end

  describe '#normalize_rate_value' do
    it 'converts extreme rate values' do
      expect(formatter.send(:normalize_rate_value, 'x-slow')).to eq('slow')
      expect(formatter.send(:normalize_rate_value, 'X-SLOW')).to eq('slow')
      expect(formatter.send(:normalize_rate_value, 'x-fast')).to eq('fast')
      expect(formatter.send(:normalize_rate_value, 'X-FAST')).to eq('fast')
    end

    it 'preserves normal rate values' do
      expect(formatter.send(:normalize_rate_value, 'medium')).to eq('medium')
      expect(formatter.send(:normalize_rate_value, 'slow')).to eq('slow')
      expect(formatter.send(:normalize_rate_value, 'fast')).to eq('fast')
    end
  end
end
