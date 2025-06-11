# frozen_string_literal: true

require 'ruby_llm'
require_relative '../analysis/prosodic_pattern'

module ProsodicTextConverter
  # Language model interface using RubyLLM
  class LLMConverter
    def initialize(provider: :openai, model: 'gpt-4', **options)
      @provider = provider
      @model = model
      @options = options
      @client = RubyLLM.new(provider: @provider, **@options)
    end

    def convert_text(text, pattern, chunks)
      system_prompt = build_system_prompt
      user_prompt = build_conversion_prompt(text, pattern, chunks)
      
      response = @client.chat(
        model: @model,
        messages: [
          { role: 'system', content: system_prompt },
          { role: 'user', content: user_prompt }
        ],
        max_tokens: 2000,
        temperature: 0.3
      )
      
      response.dig('content') || response.dig('message', 'content') || 
        raise("Unexpected response format: #{response}")
    end

    private

    def build_system_prompt
      <<~SYSTEM
        You are an expert in speech synthesis and prosodic text formatting. 
        Your task is to convert regular text into SSML format that matches specific prosodic patterns.
        
        Always:
        - Maintain the original meaning and intent
        - Use proper SSML syntax with <prosody> and <break> tags
        - Wrap output in <speak> tags
        - Create natural-sounding speech patterns
        - Vary pitch subtly for engaging delivery
      SYSTEM
    end

    def build_conversion_prompt(text, pattern, chunks)
      <<~PROMPT
        Convert this text to match the specified prosodic pattern for text-to-speech synthesis.

        PROSODIC PATTERN:
        - Segment duration: #{pattern.segment_duration}s (#{optimal_words_per_chunk(pattern)} words max per segment)
        - Pause duration: #{(pattern.pause_duration * 1000).to_i}ms between segments
        - Pitch variation: ±#{pattern.pitch_variation}% between segments
        - Speaking rate: #{pattern.rate}

        ORIGINAL TEXT:
        #{text}

        SUGGESTED CHUNKING:
        #{chunks.join(' | ')}

        FORMATTING REQUIREMENTS:
        1. Break into #{chunks.length} segments of ~#{pattern.segment_duration}s each
        2. Use <break time="#{(pattern.pause_duration * 1000).to_i}ms"/> between segments
        3. Apply <prosody> tags with subtle pitch variations (±#{pattern.pitch_variation}%)
        4. Maintain semantic coherence across chunk boundaries
        5. Return ONLY the SSML markup wrapped in <speak> tags

        Example format:
        <speak>
        <prosody rate="#{pattern.rate}" pitch="+2%">First segment</prosody>
        <break time="#{(pattern.pause_duration * 1000).to_i}ms"/>
        <prosody rate="#{pattern.rate}" pitch="-1%">Second segment</prosody>
        </speak>
      PROMPT
    end

    def optimal_words_per_chunk(pattern)
      base_wpm = { 'slow' => 120, 'medium' => 150, 'fast' => 180 }[pattern.rate] || 150
      ((base_wpm / 60.0) * pattern.segment_duration).round
    end
  end
end