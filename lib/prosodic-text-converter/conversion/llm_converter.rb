# frozen_string_literal: true

require 'ruby_llm'
require 'timeout'
require_relative '../core/logging'
require_relative '../analysis/prosodic_pattern'

module ProsodicTextConverter
  # Configure RubyLLM with environment variables
  # This initialization ensures API keys are loaded from the environment
  def self.configure_llm
    RubyLLM.configure do |config|
      config.openai_api_key = ENV.fetch('OPENAI_API_KEY', nil)
      config.gemini_api_key = ENV.fetch('GEMINI_API_KEY', nil)
      config.anthropic_api_key = ENV.fetch('ANTHROPIC_API_KEY', nil)
      config.openrouter_api_key = ENV.fetch('OPENROUTER_API_KEY', nil)
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
  end
end

# Initialize LLM configuration
ProsodicTextConverter.configure_llm

module ProsodicTextConverter
  # Language model interface using RubyLLM for text-to-SSML conversion
  #
  # @example Basic usage
  #   converter = LLMConverter.new(provider: :gemini, model: 'gemini-2.0-flash')
  #   ssml = converter.convert_text("Hello world", pattern, chunks)
  class LLMConverter
    include Logging
    
    # @return [Symbol] LLM provider
    attr_reader :provider

    # @return [String] model name
    attr_reader :model

    # Initialize LLM converter
    #
    # @param provider [Symbol] LLM provider (:gemini, :openai, :anthropic, etc.)
    # @param model [String] model name
    # @param options [Hash] additional options for LLM client
    # @raise [RuntimeError] if initialization fails
    def initialize(provider: :gemini, model: 'gemini-2.0-flash', **options)
      @provider = provider
      @model = model
      @options = options

      begin
        logger.info("Initializing LLM converter with #{@provider}:#{@model}")

        # Validate provider and model
        validate_configuration

        # Initialize client with timeout
        @client = Timeout.timeout(30) do
          RubyLLM.chat(provider: @provider, **@options)
        end

        logger.info('LLM converter initialized successfully')
      rescue Timeout::Error
        error_msg = 'Timeout initializing LLM client'
        logger.error(error_msg)
        raise error_msg.to_s
      rescue StandardError => e
        error_msg = "Failed to initialize LLM converter: #{e.message}"
        logger.error(error_msg)
        logger.debug("Backtrace: #{e.backtrace.join("\n")}")
        raise error_msg.to_s
      end
    end

    # Rephrase text to better match prosodic pattern using Systemic Functional Linguistics
    #
    # @param text_analysis [Hash] structured text analysis from TextAnalyzer
    # @param pattern [ProsodicPattern] prosodic pattern to target
    # @param options [Hash] rephrasing options
    # @option options [String] :aggressiveness ('conservative', 'medium', 'aggressive')
    # @option options [Float] :meaning_threshold (0.0-1.0) semantic similarity requirement
    # @option options [Integer] :timeout timeout in seconds
    # @return [Hash] updated text analysis with rephrased text
    # @raise [ArgumentError] if inputs are invalid
    # @raise [RuntimeError] if rephrasing fails
    def rephrase_for_prosody(text_analysis, pattern, options = {})
      validate_analysis_inputs(text_analysis, pattern)
      
      aggressiveness = options[:aggressiveness] || 'medium'
      meaning_threshold = options[:meaning_threshold] || 0.8
      timeout = options[:timeout] || 45
      
      begin
        original_text = text_analysis[:original_text]
        logger.info("Rephrasing text for prosodic fit using SFL principles (#{original_text.length} chars, #{aggressiveness} aggressiveness)")
        start_time = Time.now

        # Build SFL-informed rephrasing prompts
        system_prompt = build_sfl_rephrasing_system_prompt
        user_prompt = build_sfl_rephrasing_user_prompt(text_analysis, pattern, aggressiveness)

        logger.debug("Sending SFL-based rephrasing request to #{@provider}:#{@model}")

        # Make LLM request with timeout and retries
        response = with_retries(max_attempts: 3) do
          Timeout.timeout(timeout) do
            full_prompt = "#{system_prompt}\n\n#{user_prompt}"
            @client.with_model(@model).with_temperature(0.3).ask(full_prompt)
          end
        end

        # Extract rephrased text
        rephrased_text = extract_response_content(response)
        
        # Validate meaning preservation (basic length and keyword check for now)
        unless validate_meaning_preservation(original_text, rephrased_text, meaning_threshold)
          logger.warn("Rephrased text failed meaning preservation check, using original")
          return text_analysis
        end

        rephrasing_time = Time.now - start_time
        logger.info("SFL-based text rephrasing completed in #{rephrasing_time.round(2)}s")
        logger.debug("Original: #{original_text}")
        logger.debug("Rephrased: #{rephrased_text}")

        # Re-analyze the rephrased text
        require_relative '../text/text_analyzer'
        analyzer = TextAnalyzer.new(language: text_analysis[:language])
        updated_analysis = analyzer.analyze(rephrased_text)
        
        # Preserve original text reference for comparison
        updated_analysis[:original_text_before_rephrasing] = original_text
        updated_analysis[:rephrasing_applied] = true
        updated_analysis[:rephrasing_time] = rephrasing_time
        
        updated_analysis
      rescue Timeout::Error
        error_msg = "Text rephrasing timed out after #{timeout} seconds"
        logger.error(error_msg)
        raise error_msg.to_s
      rescue StandardError => e
        error_msg = "Text rephrasing failed: #{e.message}"
        logger.error(error_msg)
        logger.debug("Backtrace: #{e.backtrace.join("\n")}")
        raise error_msg.to_s
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
        logger.info("Converting text to SSML (#{text.length} chars, #{text_analysis[:sentence_count]} sentences)")
        start_time = Time.now

        # Build prompts with structured analysis
        system_prompt = build_system_prompt
        user_prompt = build_analysis_conversion_prompt(text_analysis, pattern)

        logger.debug("Sending request to #{@provider}:#{@model}")

        # Make LLM request with timeout and retries
        response = with_retries(max_attempts: 3) do
          Timeout.timeout(90) do # 90 second timeout for LLM
            # Combine system and user prompts for simplicity
            full_prompt = "#{system_prompt}\n\n#{user_prompt}"
            @client.with_model(@model).with_temperature(0.3).ask(full_prompt)
          end
        end

        # Extract content from response
        ssml_content = extract_response_content(response)

        conversion_time = Time.now - start_time
        logger.info("LLM conversion completed in #{conversion_time.round(2)}s")
        logger.debug("Generated SSML length: #{ssml_content.length} chars")

        ssml_content
      rescue Timeout::Error
        error_msg = 'LLM conversion timed out after 90 seconds'
        logger.error(error_msg)
        raise error_msg.to_s
      rescue StandardError => e
        error_msg = "LLM conversion failed: #{e.message}"
        logger.error(error_msg)
        logger.debug("Backtrace: #{e.backtrace.join("\n")}")
        raise error_msg.to_s
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
        logger.info("Converting text to SSML (#{text.length} chars, #{chunks.length} chunks)")
        start_time = Time.now

        # Build prompts
        system_prompt = build_system_prompt
        user_prompt = build_conversion_prompt(text, pattern, chunks)

        logger.debug("Sending request to #{@provider}:#{@model}")

        # Make LLM request with timeout and retries
        response = with_retries(max_attempts: 3) do
          Timeout.timeout(90) do # 90 second timeout for LLM
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
        logger.info("LLM conversion completed in #{conversion_time.round(2)}s")
        logger.debug("Generated SSML length: #{ssml_content.length} chars")

        ssml_content
      rescue Timeout::Error
        error_msg = 'LLM conversion timed out after 90 seconds'
        logger.error(error_msg)
        raise error_msg.to_s
      rescue StandardError => e
        error_msg = "LLM conversion failed: #{e.message}"
        logger.error(error_msg)
        logger.debug("Backtrace: #{e.backtrace.join("\n")}")
        raise error_msg.to_s
      end
    end

    private

    # Validate configuration parameters
    #
    # @raise [ArgumentError] if configuration is invalid
    def validate_configuration
      unless @provider.is_a?(Symbol) && !@provider.to_s.empty?
        error_msg = 'Provider must be a non-empty symbol'
        logger.error(error_msg)
        raise ArgumentError, error_msg
      end

      unless @model.is_a?(String) && !@model.strip.empty?
        error_msg = 'Model must be a non-empty string'
        logger.error(error_msg)
        raise ArgumentError, error_msg
      end

      logger.debug("Configuration validated: #{@provider}:#{@model}")
    end

    # Validate convert_text inputs
    #
    # @param text [String] input text
    # @param pattern [ProsodicPattern] prosodic pattern
    # @param chunks [Array] text chunks
    # @raise [ArgumentError] if inputs are invalid
    def validate_inputs(text, pattern, chunks)
      if text.nil? || text.strip.empty?
        error_msg = 'Text cannot be nil or empty'
        logger.error(error_msg)
        raise ArgumentError, error_msg
      end

      unless pattern.respond_to?(:segment_duration) && pattern.respond_to?(:pause_duration)
        error_msg = 'Pattern must respond to segment_duration and pause_duration'
        logger.error(error_msg)
        raise ArgumentError, error_msg
      end

      return if chunks.is_a?(Array) && !chunks.empty?

      error_msg = 'Chunks must be a non-empty array'
      logger.error(error_msg)
      raise ArgumentError, error_msg
    end

    # Validate convert_text_with_analysis inputs
    #
    # @param text_analysis [Hash] structured text analysis
    # @param pattern [ProsodicPattern] prosodic pattern
    # @raise [ArgumentError] if inputs are invalid
    def validate_analysis_inputs(text_analysis, pattern)
      unless text_analysis.is_a?(Hash) && text_analysis[:original_text]
        error_msg = 'Text analysis must be a hash with :original_text key'
        logger.error(error_msg)
        raise ArgumentError, error_msg
      end

      text = text_analysis[:original_text]
      if text.nil? || text.strip.empty?
        error_msg = 'Original text in analysis cannot be nil or empty'
        logger.error(error_msg)
        raise ArgumentError, error_msg
      end

      unless pattern.respond_to?(:segment_duration) && pattern.respond_to?(:pause_duration)
        error_msg = 'Pattern must respond to segment_duration and pause_duration'
        logger.error(error_msg)
        raise ArgumentError, error_msg
      end

      return if text_analysis[:sentences].is_a?(Array) && !text_analysis[:sentences].empty?

      error_msg = 'Text analysis must contain non-empty sentences array'
      logger.error(error_msg)
      raise ArgumentError, error_msg
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
          logger.warn("LLM request attempt #{attempt}/#{max_attempts} failed: #{e.message}")

          if attempt < max_attempts
            sleep_time = 2**attempt # Exponential backoff
            logger.debug("Retrying in #{sleep_time} seconds...")
            sleep(sleep_time)
          end
        end
      end

      error_msg = "All #{max_attempts} LLM request attempts failed. Last error: #{last_error.message}"
      logger.error(error_msg)
      raise error_msg.to_s
    end

    # Extract content from LLM response
    #
    # @param response [String, Hash, RubyLLM::Message] LLM response
    # @return [String] extracted content
    # @raise [RuntimeError] if content extraction fails
    def extract_response_content(response)
      # Handle different response types
      content = case response
                when String
                  response
                when RubyLLM::Message
                  response.content || response.to_s
                else
                  # Fallback for hash responses
                  response.dig('content') || response.dig('message', 'content') || response.to_s
                end

      if content.nil? || content.strip.empty?
        error_msg = "No content found in LLM response: #{response.inspect}"
        logger.error(error_msg)
        raise error_msg.to_s
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
        You are an expert in speech synthesis and prosodic text formatting.#{' '}
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
          (pause_hints ? " (#{pause_hints})" : '')
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

    # Build system prompt for SFL-based text rephrasing
    #
    # @return [String] system prompt incorporating SFL principles
    def build_sfl_rephrasing_system_prompt
      <<~SYSTEM
        You are an expert in Systemic Functional Linguistics (SFL) and prosodic text optimization for speech synthesis.
        Your task is to rephrase text to better match specific prosodic patterns while preserving meaning through SFL principles.

        SFL Framework for Rephrasing:
        1. **Ideational Metafunction**: Preserve the core experiential meaning (who does what, when, where, how)
        2. **Interpersonal Metafunction**: Maintain the speaker's attitude, mood, and relationship with audience
        3. **Textual Metafunction**: Optimize information flow and thematic structure for prosodic constraints

        Key SFL Strategies for Prosodic Optimization:
        - **Thematic Progression**: Reorganize Theme-Rheme structure to fit segment boundaries
        - **Information Packaging**: Use Given-New information flow to guide pause placement
        - **Cohesive Devices**: Employ reference, substitution, ellipsis to manage segment length
        - **Transitivity Patterns**: Adjust process types and participant roles for optimal rhythm
        - **Mood and Modality**: Preserve interpersonal meaning while adjusting clause structure
        - **Nominalization**: Convert clauses to nominal groups or vice versa for length control
        - **Hypotaxis/Parataxis**: Adjust clause combining for prosodic boundaries

        Always:
        - Preserve semantic content and pragmatic force
        - Maintain register and stylistic consistency
        - Optimize clause boundaries for natural speech rhythm
        - Consider information prominence and focus structure
        - Respect genre conventions and communicative purpose
      SYSTEM
    end

    # Build user prompt for SFL-based rephrasing
    #
    # @param text_analysis [Hash] structured text analysis
    # @param pattern [ProsodicPattern] target prosodic pattern
    # @param aggressiveness [String] rephrasing intensity level
    # @return [String] user prompt with SFL analysis and constraints
    def build_sfl_rephrasing_user_prompt(text_analysis, pattern, aggressiveness)
      text = text_analysis[:original_text]
      sentences = text_analysis[:sentences]
      target_words_per_segment = optimal_words_per_chunk(pattern)

      # Analyze current prosodic challenges
      prosodic_analysis = analyze_prosodic_challenges(sentences, pattern)
      
      # Set aggressiveness constraints
      aggressiveness_constraints = case aggressiveness
      when 'conservative'
        'Minimal changes: Only adjust clause boundaries and add/remove short function words'
      when 'medium'  
        'Moderate changes: Reorganize information structure, adjust clause combining, use cohesive devices'
      when 'aggressive'
        'Significant changes: Complete thematic restructuring, transitivity changes, nominalization/de-nominalization'
      else
        'Moderate changes: Reorganize information structure, adjust clause combining, use cohesive devices'
      end

      <<~PROMPT
        Rephrase this text using SFL principles to optimize it for the specified prosodic pattern.

        ORIGINAL TEXT:
        #{text}

        PROSODIC TARGET:
        - Segment duration: #{pattern.segment_duration}s (≈#{target_words_per_segment} words per segment)
        - Pause duration: #{(pattern.pause_duration * 1000).to_i}ms between segments
        - Speaking rate: #{pattern.rate}
        - Pitch variation: ±#{pattern.pitch_variation}%

        CURRENT PROSODIC ANALYSIS:
        #{prosodic_analysis}

        SFL REPHRASING CONSTRAINTS:
        #{aggressiveness_constraints}

        SFL OPTIMIZATION STRATEGIES TO APPLY:
        1. **Thematic Structure**: Reorganize Theme-Rheme to align with segment boundaries
        2. **Information Flow**: Package Given-New information for natural pause points
        3. **Clause Complexity**: Adjust hypotaxis/parataxis for target segment length
        4. **Cohesion**: Use reference chains and cohesive devices to manage segment transitions
        5. **Transitivity**: Modify process-participant structures if needed for rhythm
        6. **Mood/Modality**: Preserve interpersonal meaning while optimizing structure

        REQUIREMENTS:
        - Preserve all semantic content and communicative function
        - Maintain original register, style, and interpersonal relationships
        - Optimize clause boundaries for #{(pattern.pause_duration * 1000).to_i}ms pauses
        - Target #{target_words_per_segment} words per prosodic segment
        - Ensure smooth information flow across segment boundaries
        - Return ONLY the rephrased text, no explanations or markup

        Example transformation:
        Original: "The company announced quarterly results which exceeded expectations significantly."
        SFL-optimized: "The company announced quarterly results. These results exceeded expectations significantly."
        (Splits long clause at natural information boundary for better prosodic segmentation)
      PROMPT
    end

    # Analyze prosodic challenges in current text structure
    #
    # @param sentences [Array<Hash>] sentence analysis data
    # @param pattern [ProsodicPattern] target prosodic pattern
    # @return [String] analysis of current prosodic challenges
    def analyze_prosodic_challenges(sentences, pattern)
      target_words = optimal_words_per_chunk(pattern)
      challenges = []

      sentences.each_with_index do |sentence, idx|
        word_count = sentence[:word_count]
        
        if word_count > target_words * 1.5
          challenges << "Sentence #{idx + 1}: #{word_count} words (too long, needs segmentation)"
        elsif word_count < target_words * 0.5
          challenges << "Sentence #{idx + 1}: #{word_count} words (too short, could be combined)"
        end

        # Check for complex subordination that might need restructuring
        if sentence[:pause_indicators].include?('subordination')
          challenges << "Sentence #{idx + 1}: Complex subordination (consider clause reorganization)"
        end
      end

      challenges.empty? ? "Text structure aligns well with prosodic targets" : challenges.join("\n")
    end

    # Validate meaning preservation between original and rephrased text
    #
    # @param original [String] original text
    # @param rephrased [String] rephrased text
    # @param threshold [Float] minimum similarity threshold (0.0-1.0)
    # @return [Boolean] true if meaning is preserved
    def validate_meaning_preservation(original, rephrased, threshold)
      # Basic validation: length similarity and key content preservation
      # In a production system, this would use semantic similarity models
      
      # Length check: rephrased text shouldn't be dramatically different in length
      length_ratio = [original.length, rephrased.length].min.to_f / [original.length, rephrased.length].max
      return false if length_ratio < 0.5  # Too different in length
      
      # Word overlap check: should preserve most content words
      original_words = original.downcase.gsub(/[^\w\s]/, '').split
      rephrased_words = rephrased.downcase.gsub(/[^\w\s]/, '').split
      
      # Filter out common function words
      function_words = %w[the a an and or but in on at to for of with by from that this these those is are was were be been have has had do does did will would could should may might]
      original_content = original_words - function_words
      rephrased_content = rephrased_words - function_words
      
      return true if original_content.empty? # Edge case
      
      # Calculate content word overlap
      overlap = (original_content & rephrased_content).length
      content_preservation = overlap.to_f / original_content.length
      
      logger.debug("Meaning preservation check: length_ratio=#{length_ratio.round(2)}, content_preservation=#{content_preservation.round(2)}")
      
      content_preservation >= threshold
    end
  end
end
