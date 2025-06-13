# frozen_string_literal: true

require_relative '../conversion/elevenlabs_formatter'

module ProsodicTextConverter
  # Speech synthesis module for generating audio from SSML
  #
  # Supports multiple speech synthesis providers with a unified interface.
  # Currently implements ElevenLabs integration with extensible architecture
  # for additional providers.
  #
  # @example Basic usage
  #   synthesizer = SpeechSynthesizer.new(provider: :elevenlabs)
  #   audio_data = synthesizer.synthesize_ssml(ssml_text, voice: 'voice_id')
  #   synthesizer.save_audio(audio_data, 'output.mp3')
  class SpeechSynthesizer
    # Available speech synthesis providers
    PROVIDERS = {
      elevenlabs: 'ElevenLabs'
    }.freeze

    # Initialize speech synthesizer
    #
    # @param provider [Symbol] speech synthesis provider (:elevenlabs)
    # @param api_key [String] provider API key (optional, can use environment variable)
    # @param config [Config] configuration object for model capabilities
    def initialize(provider: :elevenlabs, api_key: nil, config: nil)
      @provider = provider
      @config = config
      @formatter = create_formatter(provider, api_key, config)
    end

    # Synthesize speech from SSML text
    #
    # @param ssml_text [String] SSML markup text
    # @param voice [String] voice identifier for the provider
    # @param options [Hash] provider-specific options
    # @return [String] binary audio data
    def synthesize_ssml(ssml_text, voice:, **options)
      case @provider
      when :elevenlabs
        @formatter.synthesize_speech(ssml_text, voice, **options)
      else
        raise ArgumentError, "Unsupported provider: #{@provider}"
      end
    end

    # Synthesize speech from plain text (converts to basic SSML first)
    #
    # @param text [String] plain text to synthesize
    # @param voice [String] voice identifier for the provider
    # @param options [Hash] provider-specific options
    # @return [String] binary audio data
    def synthesize_text(text, voice:, **options)
      ssml = wrap_in_speak_tags(text)
      synthesize_ssml(ssml, voice: voice, **options)
    end

    # Get available voices for the current provider
    #
    # @return [Array<Hash>] array of voice objects
    def get_voices
      case @provider
      when :elevenlabs
        @formatter.get_voices
      else
        raise ArgumentError, "Unsupported provider: #{@provider}"
      end
    end

    # Save audio data to file
    #
    # @param audio_data [String] binary audio data
    # @param filename [String] output filename
    # @param format [String] audio format (auto-detected from filename if not specified)
    def save_audio(audio_data, filename, format: nil)
      format ||= detect_format_from_filename(filename)

      File.open(filename, 'wb') do |file|
        file.write(audio_data)
      end

      puts "Audio saved to: #{filename} (#{format.upcase}, #{audio_data.bytesize} bytes)"
    end

    # Convert SSML to provider-compatible format
    #
    # @param ssml_text [String] standard SSML markup
    # @param model_id [String] provider-specific model identifier
    # @return [String] provider-compatible SSML
    def convert_ssml_format(ssml_text, model_id: nil)
      case @provider
      when :elevenlabs
        @formatter.convert_to_elevenlabs_format(ssml_text, model_id: model_id)
      else
        ssml_text # Return unchanged for unsupported providers
      end
    end

    # Get provider-specific format information
    #
    # @return [Hash] format specifications and limitations
    def get_format_info
      case @provider
      when :elevenlabs
        {
          provider: 'ElevenLabs',
          max_break_duration: ElevenLabsFormatter::MAX_BREAK_DURATION,
          supported_tags: %w[speak break prosody emphasis phoneme],
          phoneme_models: ElevenLabsFormatter::PHONEME_SUPPORTED_MODELS,
          default_format: 'mp3',
          supported_formats: %w[mp3 wav ogg]
        }
      else
        { provider: @provider.to_s }
      end
    end

    # Check if provider supports specific features
    #
    # @param feature [Symbol] feature to check (:phonemes, :long_breaks, :prosody)
    # @param model_id [String] model identifier for model-specific features
    # @return [Boolean] true if feature is supported
    def supports_feature?(feature, model_id: nil)
      case @provider
      when :elevenlabs
        case feature
        when :phonemes
          model_id && ElevenLabsFormatter::PHONEME_SUPPORTED_MODELS.include?(model_id)
        when :long_breaks
          false # ElevenLabs caps breaks at 3 seconds
        when :prosody
          true
        when :emphasis
          true
        else
          false
        end
      else
        false
      end
    end

    private

    # Create formatter instance for the specified provider
    #
    # @param provider [Symbol] provider identifier
    # @param api_key [String] API key
    # @param config [Config] configuration object
    # @return [Object] formatter instance
    def create_formatter(provider, api_key, config)
      case provider
      when :elevenlabs
        ElevenLabsFormatter.new(api_key: api_key, config: config)
      else
        raise ArgumentError, "Unsupported provider: #{provider}. Available: #{PROVIDERS.keys.join(', ')}"
      end
    end

    # Wrap plain text in SSML speak tags
    #
    # @param text [String] plain text
    # @return [String] basic SSML markup
    def wrap_in_speak_tags(text)
      "<speak>#{text}</speak>"
    end

    # Detect audio format from filename extension
    #
    # @param filename [String] output filename
    # @return [String] detected format
    def detect_format_from_filename(filename)
      ext = File.extname(filename).downcase.gsub('.', '')
      ext.empty? ? 'mp3' : ext
    end
  end
end
