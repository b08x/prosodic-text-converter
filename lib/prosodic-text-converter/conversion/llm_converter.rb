# frozen_string_literal: true

require 'ruby_llm'
require 'logger'
require 'timeout'
require_relative '../analysis/prosodic_pattern'

RubyLLM.configure do |config|
  config.openai_api_key = ENV.fetch('OPENAI_API_KEY', nil)
  config.gemini_api_key = ENV.fetch('GEMINI_API_KEY', nil)
  config.openai_api_base = ENV.fetch('OPENAI_API_BASE', nil)
  config.default_model = 'gemini-2.0-flash'
  config.default_embedding_model = 'text-embedding-004'
  config.default_image_model = 'imagen-3.0-generate-002'
  config.request_timeout = 120
  config.max_retries = 3
  config.retry_interval = 0.5
  config.retry_backoff_factor = 2
  config.retry_interval_randomness = 0.5
end


module ProsodicTextConverter
  # Language model interface using RubyLLM for text-to-SSML conversion
  #
  # @example Basic usage
  #   converter = LLMConverter.new(provider: :gemini, model: 'gemini-2.0-flash')
  #   ssml = converter.convert_text("Hello world", pattern, chunks)
  class LLMConverter
    # @return [Symbol] LLM provider
    attr_reader :provider
    
    # @return [String] model name
    attr_reader :model
    
    # @return [Logger] logger instance
    attr_reader :logger

    # Initialize LLM converter
    #
    # @param provider [Symbol] LLM provider (:gemini, :openai, :anthropic, etc.)
    # @param model [String] model name
    # @param logger [Logger, nil] custom logger instance
    # @param options [Hash] additional options for LLM client
    # @raise [RuntimeError] if initialization fails
    def initialize(provider: :gemini, model: 'gemini-2.0-flash', logger: nil, **options)
      @provider = provider
      @model = model
      @options = options
      @logger = logger || setup_logger
      
      begin
        @logger.info("Initializing LLM converter with #{@provider}:#{@model}")
        
        # Validate provider and model
        validate_configuration
        
        # Initialize client with timeout
        @client = Timeout.timeout(30) do
          RubyLLM.chat(provider: @provider, **@options)
        end
        
        @logger.info("LLM converter initialized successfully")
        
      rescue Timeout::Error
        error_msg = "Timeout initializing LLM client"
        @logger.error(error_msg)
        raise RuntimeError, error_msg
      rescue StandardError => e
        error_msg = "Failed to initialize LLM converter: #{e.message}"
        @logger.error(error_msg)
        @logger.debug("Backtrace: #{e.backtrace.join("\n")}")
        raise RuntimeError, error_msg
      end
    end

    # Convert text to SSML using structured text analysis
    #
    # @param text_analysis [Hash] structured text analysis from TextAnalyzer
    # @param pattern [ProsodicPattern] prosodic pattern to apply
    # @return [String] SSML output
    # @raise [ArgumentError] if inputs are invalid
    # @raise [RuntimeError] if conversion fails
    def convert_text_with_analysis(text_analysis, pattern)
      validate_analysis_inputs(text_analysis, pattern)
      
      begin
        text = text_analysis[:original_text]
        @logger.info("Converting text to SSML (#{text.length} chars, #{text_analysis[:sentence_count]} sentences)")
        start_time = Time.now
        
        # Build prompts with structured analysis
        system_prompt = build_system_prompt
        user_prompt = build_analysis_conversion_prompt(text_analysis, pattern)
        
        @logger.debug("Sending request to #{@provider}:#{@model}")
        
        # Make LLM request with timeout and retries
        response = with_retries(max_attempts: 3) do
          Timeout.timeout(90) do  # 90 second timeout for LLM
            # Combine system and user prompts for simplicity
            full_prompt = "#{system_prompt}\n\n#{user_prompt}"
            @client.with_model(@model).with_temperature(0.3).ask(full_prompt)
          end
        end
        
        # Extract content from response
        ssml_content = extract_response_content(response)
        
        conversion_time = Time.now - start_time
        @logger.info("LLM conversion completed in #{conversion_time.round(2)}s")
        @logger.debug("Generated SSML length: #{ssml_content.length} chars")
        
        ssml_content
        
      rescue Timeout::Error => e
        error_msg = "LLM conversion timed out after 90 seconds"
        @logger.error(error_msg)
        raise RuntimeError, error_msg
      rescue StandardError => e
        error_msg = "LLM conversion failed: #{e.message}"
        @logger.error(error_msg)
        @logger.debug("Backtrace: #{e.backtrace.join("\n")}")
        raise RuntimeError, error_msg
      end
    end

    # Convert text to SSML using LLM (legacy interface)
    #
    # @param text [String] input text to convert
    # @param pattern [ProsodicPattern] prosodic pattern to apply
    # @param chunks [Array<String>] text chunks for segmentation
    # @return [String] SSML output
    # @raise [ArgumentError] if inputs are invalid
    # @raise [RuntimeError] if conversion fails
    def convert_text(text, pattern, chunks)
      validate_inputs(text, pattern, chunks)
      
      begin
        @logger.info("Converting text to SSML (#{text.length} chars, #{chunks.length} chunks)")
        start_time = Time.now
        
        # Build prompts
        system_prompt = build_system_prompt
        user_prompt = build_conversion_prompt(text, pattern, chunks)
        
        @logger.debug("Sending request to #{@provider}:#{@model}")
        
        # Make LLM request with timeout and retries
        response = with_retries(max_attempts: 3) do
          Timeout.timeout(90) do  # 90 second timeout for LLM
            @client.chat(
              model: @model,
              messages: [
                { role: 'system', content: system_prompt },
                { role: 'user', content: user_prompt }
              ],
              max_tokens: 2000,
              temperature: 0.3
            )
          end
        end
        
        # Extract content from response
        ssml_content = extract_response_content(response)
        
        conversion_time = Time.now - start_time
        @logger.info("LLM conversion completed in #{conversion_time.round(2)}s")
        @logger.debug("Generated SSML length: #{ssml_content.length} chars")
        
        ssml_content
        
      rescue Timeout::Error => e
        error_msg = "LLM conversion timed out after 90 seconds"
        @logger.error(error_msg)
        raise RuntimeError, error_msg
      rescue StandardError => e
        error_msg = "LLM conversion failed: #{e.message}"
        @logger.error(error_msg)
        @logger.debug("Backtrace: #{e.backtrace.join("\n")}")
        raise RuntimeError, error_msg
      end
    end

    private

    # Setup logger instance
    #
    # @return [Logger] configured logger
    def setup_logger
      Logger.new($stderr).tap do |log|
        log.level = Logger::INFO
        log.formatter = proc do |severity, datetime, progname, msg|
          "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] LLMConverter #{severity}: #{msg}\n"
        end
      end
    end

    # Validate configuration parameters
    #
    # @raise [ArgumentError] if configuration is invalid
    def validate_configuration
      unless @provider.is_a?(Symbol) && !@provider.to_s.empty?
        error_msg = "Provider must be a non-empty symbol"
        @logger.error(error_msg)
        raise ArgumentError, error_msg
      end
      
      unless @model.is_a?(String) && !@model.strip.empty?
        error_msg = "Model must be a non-empty string"
        @logger.error(error_msg)
        raise ArgumentError, error_msg
      end
      
      @logger.debug("Configuration validated: #{@provider}:#{@model}")
    end

    # Validate convert_text inputs
    #
    # @param text [String] input text
    # @param pattern [ProsodicPattern] prosodic pattern
    # @param chunks [Array] text chunks
    # @raise [ArgumentError] if inputs are invalid
    def validate_inputs(text, pattern, chunks)
      if text.nil? || text.strip.empty?
        error_msg = "Text cannot be nil or empty"
        @logger.error(error_msg)
        raise ArgumentError, error_msg
      end
      
      unless pattern.respond_to?(:segment_duration) && pattern.respond_to?(:pause_duration)
        error_msg = "Pattern must respond to segment_duration and pause_duration"
        @logger.error(error_msg)
        raise ArgumentError, error_msg
      end
      
      unless chunks.is_a?(Array) && !chunks.empty?
        error_msg = "Chunks must be a non-empty array"
        @logger.error(error_msg)
        raise ArgumentError, error_msg
      end
    end

    # Validate convert_text_with_analysis inputs
    #
    # @param text_analysis [Hash] structured text analysis
    # @param pattern [ProsodicPattern] prosodic pattern
    # @raise [ArgumentError] if inputs are invalid
    def validate_analysis_inputs(text_analysis, pattern)
      unless text_analysis.is_a?(Hash) && text_analysis[:original_text]
        error_msg = "Text analysis must be a hash with :original_text key"
        @logger.error(error_msg)
        raise ArgumentError, error_msg
      end
      
      text = text_analysis[:original_text]
      if text.nil? || text.strip.empty?
        error_msg = "Original text in analysis cannot be nil or empty"
        @logger.error(error_msg)
        raise ArgumentError, error_msg
      end
      
      unless pattern.respond_to?(:segment_duration) && pattern.respond_to?(:pause_duration)
        error_msg = "Pattern must respond to segment_duration and pause_duration"
        @logger.error(error_msg)
        raise ArgumentError, error_msg
      end
      
      unless text_analysis[:sentences].is_a?(Array) && !text_analysis[:sentences].empty?
        error_msg = "Text analysis must contain non-empty sentences array"
        @logger.error(error_msg)
        raise ArgumentError, error_msg
      end
    end

    # Retry mechanism for LLM requests
    #
    # @param max_attempts [Integer] maximum retry attempts
    # @yield block to retry
    # @return [Object] result of yielded block
    # @raise [RuntimeError] if all attempts fail
    def with_retries(max_attempts: 3)
      attempt = 0
      last_error = nil
      
      while attempt < max_attempts
        attempt += 1
        
        begin
          return yield
        rescue StandardError => e
          last_error = e
          @logger.warn("LLM request attempt #{attempt}/#{max_attempts} failed: #{e.message}")
          
          if attempt < max_attempts
            sleep_time = 2 ** attempt  # Exponential backoff
            @logger.debug("Retrying in #{sleep_time} seconds...")
            sleep(sleep_time)
          end
        end
      end
      
      error_msg = "All #{max_attempts} LLM request attempts failed. Last error: #{last_error.message}"
      @logger.error(error_msg)
      raise RuntimeError, error_msg
    end

    # Extract content from LLM response
    #
    # @param response [String, Hash, RubyLLM::Message] LLM response
    # @return [String] extracted content
    # @raise [RuntimeError] if content extraction fails
    def extract_response_content(response)
      # Handle different response types
      case response
      when String
        content = response
      when RubyLLM::Message
        content = response.content || response.to_s
      else
        # Fallback for hash responses
        content = response.dig('content') || response.dig('message', 'content') || response.to_s
      end
      
      if content.nil? || content.strip.empty?
        error_msg = "No content found in LLM response: #{response.inspect}"
        @logger.error(error_msg)
        raise RuntimeError, error_msg
      end
      
      # Clean up markdown formatting if present
      content = content.strip
      content = content.gsub(/^```(?:xml|ssml)?\s*\n?/, '').gsub(/\n?```\s*$/, '')
      content.strip
    end

    # Build system prompt for LLM
    #
    # @return [String] system prompt
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

    # Build conversion prompt for LLM
    #
    # @param text [String] input text
    # @param pattern [ProsodicPattern] prosodic pattern
    # @param chunks [Array<String>] text chunks
    # @return [String] conversion prompt
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

    # Build conversion prompt using structured text analysis
    #
    # @param text_analysis [Hash] structured text analysis from TextAnalyzer
    # @param pattern [ProsodicPattern] prosodic pattern
    # @return [String] conversion prompt
    def build_analysis_conversion_prompt(text_analysis, pattern)
      text = text_analysis[:original_text]
      sentences = text_analysis[:sentences]
      
      # Build sentence analysis summary
      sentence_summary = sentences.map do |sent|
        pause_hints = sent[:pause_indicators].join(', ') if sent[:pause_indicators].any?
        syllables = sent[:words].sum { |w| w[:syllable_count] }
        "Sentence #{sent[:index] + 1}: #{sent[:word_count]} words, #{syllables} syllables" +
          (pause_hints ? " (#{pause_hints})" : "")
      end.join("\n")
      
      <<~PROMPT
        Convert this text to match the specified prosodic pattern for text-to-speech synthesis.
        Use the detailed linguistic analysis to make intelligent prosodic decisions.

        PROSODIC PATTERN:
        - Segment duration: #{pattern.segment_duration}s (#{optimal_words_per_chunk(pattern)} words max per segment)
        - Pause duration: #{(pattern.pause_duration * 1000).to_i}ms between segments
        - Pitch variation: ±#{pattern.pitch_variation}% between segments
        - Speaking rate: #{pattern.rate}

        ORIGINAL TEXT:
        #{text}

        LINGUISTIC ANALYSIS:
        - Language: #{text_analysis[:language]}
        - Total sentences: #{text_analysis[:sentence_count]}
        - Total syllables: #{sentences.sum { |s| s[:words].sum { |w| w[:syllable_count] } }}
        
        #{sentence_summary}

        PROSODIC CONSIDERATIONS:
        1. Use punctuation analysis to determine natural pause points
        2. Consider syllable density for timing adjustments
        3. Respect discourse markers and conjunctions for appropriate pauses
        4. Break at prosodic boundaries rather than arbitrary word counts
        5. Use pitch variation to maintain engagement while preserving meaning
        6. Adjust speaking rate based on content complexity

        FORMATTING REQUIREMENTS:
        1. Create segments that respect linguistic boundaries
        2. Use <break time="#{(pattern.pause_duration * 1000).to_i}ms"/> for major pauses
        3. Use shorter breaks (100-200ms) for comma pauses
        4. Apply <prosody> tags with subtle pitch variations (±#{pattern.pitch_variation}%)
        5. Match segment duration to #{pattern.segment_duration}s target
        6. Return ONLY the SSML markup wrapped in <speak> tags

        Example format:
        <speak>
        <prosody rate="#{pattern.rate}" pitch="+2%">First prosodic unit</prosody>
        <break time="#{(pattern.pause_duration * 1000).to_i}ms"/>
        <prosody rate="#{pattern.rate}" pitch="-1%">Second prosodic unit</prosody>
        </speak>
      PROMPT
    end

    # Calculate optimal words per chunk based on pattern
    #
    # @param pattern [ProsodicPattern] prosodic pattern
    # @return [Integer] optimal word count per chunk
    def optimal_words_per_chunk(pattern)
      base_wpm = { 'slow' => 120, 'medium' => 150, 'fast' => 180 }[pattern.rate] || 150
      ((base_wpm / 60.0) * pattern.segment_duration).round
    end
  end
end