# frozen_string_literal: true

require_relative 'ssml_formatter'

module ProsodicTextConverter
  # ElevenLabs-compatible SSML formatter
  #
  # Converts standard SSML to ElevenLabs-compatible format by:
  # - Capping break times at 3 seconds maximum
  # - Converting time units to seconds format
  # - Simplifying prosody attributes for compatibility
  # - Handling model-specific features like phonemes
  #
  # @example Basic usage
  #   formatter = ElevenLabsFormatter.new
  #   compatible_ssml = formatter.convert_to_elevenlabs_format(standard_ssml)
  #   audio_data = formatter.synthesize_speech(compatible_ssml, voice_id)
  class ElevenLabsFormatter < SSMLFormatter
    # Maximum break duration allowed by ElevenLabs API (in seconds)
    MAX_BREAK_DURATION = 3.0

    # Models that support phoneme tags
    PHONEME_SUPPORTED_MODELS = %w[
      eleven_english_v1
      eleven_flash_v2
      eleven_turbo_v2
    ].freeze

    # Initialize ElevenLabs formatter
    #
    # @param api_key [String] ElevenLabs API key
    def initialize(api_key: nil)
      super()
      @api_key = api_key || ENV['ELEVENLABS_API_KEY']
    end

    # Convert standard SSML to ElevenLabs-compatible format
    #
    # @param ssml_text [String] standard SSML markup
    # @param model_id [String] ElevenLabs model identifier
    # @return [String] ElevenLabs-compatible SSML
    def convert_to_elevenlabs_format(ssml_text, model_id: nil)
      doc = parse_ssml(ssml_text)

      # Convert and validate break times
      process_break_tags(doc)

      # Simplify prosody attributes
      process_prosody_tags(doc)

      # Handle model-specific phoneme tags
      process_phoneme_tags(doc, model_id) if model_id

      # Return cleaned XML
      doc.to_xml(save_with: Nokogiri::XML::Node::SaveOptions::NO_DECLARATION)
    end

    # Synthesize speech using ElevenLabs API
    #
    # @param ssml_text [String] ElevenLabs-compatible SSML
    # @param voice_id [String] ElevenLabs voice identifier
    # @param options [Hash] additional API options
    # @option options [String] :model_id ElevenLabs model to use
    # @option options [Float] :stability Voice stability (0.0-1.0)
    # @option options [Float] :similarity_boost Voice similarity boost (0.0-1.0)
    # @option options [String] :output_format Audio format (mp3, wav, etc.)
    # @return [String] binary audio data
    def synthesize_speech(ssml_text, voice_id, **options)
      unless @api_key
        raise ArgumentError,
              'ElevenLabs API key required. Set ELEVENLABS_API_KEY environment variable or pass api_key parameter.'
      end

      # Convert SSML to ElevenLabs format
      compatible_ssml = convert_to_elevenlabs_format(ssml_text, model_id: options[:model_id])

      # Prepare API request
      url = "https://api.elevenlabs.io/v1/text-to-speech/#{voice_id}"
      headers = {
        'Accept' => 'audio/mpeg',
        'Content-Type' => 'application/json',
        'xi-api-key' => @api_key
      }

      payload = {
        text: compatible_ssml,
        model_id: options[:model_id] || 'eleven_monolingual_v1',
        voice_settings: {
          stability: options[:stability] || 0.5,
          similarity_boost: options[:similarity_boost] || 0.75
        }
      }

      # Make API request
      make_api_request(url, headers, payload)
    end

    # Get available voices from ElevenLabs API
    #
    # @return [Array<Hash>] array of voice objects with id, name, and metadata
    def get_voices
      raise ArgumentError, 'ElevenLabs API key required' unless @api_key

      url = 'https://api.elevenlabs.io/v1/voices'
      headers = { 'xi-api-key' => @api_key }

      response = make_api_request(url, headers, nil, method: :get)
      JSON.parse(response)['voices']
    end

    private

    # Parse SSML text into Nokogiri document
    #
    # @param ssml_text [String] SSML markup
    # @return [Nokogiri::XML::Document] parsed document
    def parse_ssml(ssml_text)
      Nokogiri::XML(ssml_text) do |config|
        config.noblanks.noent
      end
    rescue Nokogiri::XML::SyntaxError => e
      raise ArgumentError, "Invalid SSML markup: #{e.message}"
    end

    # Process break tags for ElevenLabs compatibility
    #
    # @param doc [Nokogiri::XML::Document] SSML document
    def process_break_tags(doc)
      doc.css('break').each do |break_tag|
        time_attr = break_tag['time']
        next unless time_attr

        # Convert to seconds and cap at maximum
        time_seconds = convert_to_seconds(time_attr)
        capped_time = [time_seconds, MAX_BREAK_DURATION].min

        break_tag['time'] = "#{capped_time}s"
      end
    end

    # Process prosody tags for simplified attributes
    #
    # @param doc [Nokogiri::XML::Document] SSML document
    def process_prosody_tags(doc)
      doc.css('prosody').each do |prosody_tag|
        # Ensure rate values are in supported format
        prosody_tag['rate'] = normalize_rate_value(prosody_tag['rate']) if prosody_tag['rate']

        # Ensure pitch values are in supported format
        prosody_tag['pitch'] = normalize_pitch_value(prosody_tag['pitch']) if prosody_tag['pitch']
      end
    end

    # Process phoneme tags based on model compatibility
    #
    # @param doc [Nokogiri::XML::Document] SSML document
    # @param model_id [String] ElevenLabs model identifier
    def process_phoneme_tags(doc, model_id)
      return if model_supports_phonemes?(model_id)

      # Remove phoneme tags for unsupported models
      doc.css('phoneme').each do |phoneme_tag|
        phoneme_tag.replace(phoneme_tag.content)
      end
    end

    # Convert time string to seconds
    #
    # @param time_str [String] time value (e.g., "500ms", "1.5s")
    # @return [Float] time in seconds
    def convert_to_seconds(time_str)
      if time_str.end_with?('ms')
        time_str.gsub('ms', '').to_f / 1000.0
      elsif time_str.end_with?('s')
        time_str.gsub('s', '').to_f
      else
        # Assume milliseconds if no unit specified
        time_str.to_f / 1000.0
      end
    end

    # Normalize rate value for ElevenLabs compatibility
    #
    # @param rate_value [String] rate attribute value
    # @return [String] normalized rate value
    def normalize_rate_value(rate_value)
      case rate_value.downcase
      when 'x-slow' then 'slow'
      when 'x-fast' then 'fast'
      else rate_value
      end
    end

    # Normalize pitch value for ElevenLabs compatibility
    #
    # @param pitch_value [String] pitch attribute value
    # @return [String] normalized pitch value
    def normalize_pitch_value(pitch_value)
      # Ensure percentage values are within reasonable bounds
      if pitch_value.include?('%')
        percentage = pitch_value.gsub(/[+%-]/, '').to_f
        clamped = [[-50, percentage].max, 50].min
        sign = pitch_value.start_with?('-') ? '-' : '+'
        "#{sign}#{clamped}%"
      else
        pitch_value
      end
    end

    # Check if model supports phoneme tags
    #
    # @param model_id [String] ElevenLabs model identifier
    # @return [Boolean] true if model supports phonemes
    def model_supports_phonemes?(model_id)
      PHONEME_SUPPORTED_MODELS.include?(model_id)
    end

    # Make HTTP request to ElevenLabs API
    #
    # @param url [String] API endpoint URL
    # @param headers [Hash] request headers
    # @param payload [Hash] request payload (nil for GET requests)
    # @param method [Symbol] HTTP method (:get, :post)
    # @return [String] response body
    def make_api_request(url, headers, payload, method: :post)
      require 'net/http'
      require 'json'

      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = case method
                when :get
                  Net::HTTP::Get.new(uri)
                when :post
                  req = Net::HTTP::Post.new(uri)
                  req.body = payload.to_json if payload
                  req
                else
                  raise ArgumentError, "Unsupported HTTP method: #{method}"
                end

      headers.each { |key, value| request[key] = value }

      response = http.request(request)

      unless response.code.start_with?('2')
        raise StandardError, "ElevenLabs API error (#{response.code}): #{response.body}"
      end

      response.body
    end
  end
end
