# frozen_string_literal: true

require_relative '../core/logging'
require_relative '../text/text_analyzer'
require_relative '../analysis/speech_pattern_extractor'
require_relative '../conversion/llm_converter'

module ProsodicTextConverter
  # Intelligent text rewriting engine using speech pattern analysis
  #
  # This class takes extracted speech patterns from spectrograms and uses them
  # to intelligently rewrite input text for optimal prosodic matching. It combines
  # Systemic Functional Linguistics principles with speech pattern analysis to
  # create text that naturally fits the target speech characteristics.
  #
  # @example Basic usage
  #   rewriter = SpeechPatternRewriter.new(provider: :gemini)
  #   patterns = speech_pattern_extractor.extract_speech_patterns('spectrogram.png')
  #   guidance = speech_pattern_extractor.generate_rewrite_guidance(text_analysis)
  #   result = rewriter.rewrite_text(text_analysis, guidance)
  class SpeechPatternRewriter
    include Logging

    # @return [LLMConverter] LLM converter instance
    attr_reader :llm_converter

    # @return [Hash] rewriter configuration options
    attr_reader :options

    # Initialize speech pattern rewriter
    #
    # @param provider [Symbol] LLM provider (:gemini, :openai, :anthropic, etc.)
    # @param model [String] model name to use
    # @param config [Config, nil] configuration object
    # @param options [Hash] rewriter options
    # @option options [String] :rewrite_strategy ('pattern_guided', 'sfl_optimized', 'hybrid')
    # @option options [Boolean] :preserve_meaning enable strict meaning preservation
    # @option options [Float] :meaning_threshold semantic similarity threshold (0.0-1.0)
    # @option options [Boolean] :detailed_logging enable detailed rewriting logs
    # @option options [Integer] :max_iterations maximum rewrite iterations per sentence
    # @raise [RuntimeError] if initialization fails
    def initialize(provider: :gemini, model: 'gemini-2.5-flash', config: nil, **options)
      @config = config
      @options = default_options.merge(options)

      begin
        logger.info("Initializing SpeechPatternRewriter with #{provider}:#{model}")

        # Initialize LLM converter for text rewriting
        @llm_converter = LLMConverter.new(
          provider: provider,
          model: model,
          config: config
        )

        # Initialize text analyzer for re-analysis
        @text_analyzer = TextAnalyzer.new(language: :en)

        logger.info('SpeechPatternRewriter initialized successfully')
      rescue StandardError => e
        error_msg = "Failed to initialize SpeechPatternRewriter: #{e.message}"
        logger.error(error_msg)
        raise error_msg
      end
    end

    # Rewrite text using extracted speech patterns and guidance
    #
    # @param text_analysis [Hash] structured text analysis from TextAnalyzer
    # @param rewrite_guidance [Hash] guidance from SpeechPatternExtractor
    # @param options [Hash] rewriting options
    # @option options [String] :strategy override default rewrite strategy
    # @option options [Boolean] :iterative_refinement enable multiple rewrite passes
    # @option options [Integer] :max_iterations maximum rewrite iterations
    # @return [Hash] rewriting results with original and rewritten text
    # @raise [ArgumentError] if inputs are invalid
    # @raise [RuntimeError] if rewriting fails
    def rewrite_text(text_analysis, rewrite_guidance, options = {})
      validate_rewrite_inputs(text_analysis, rewrite_guidance)

      rewrite_options = @options.merge(options)
      strategy = rewrite_options[:strategy] || rewrite_guidance[:overall_strategy][:primary_focus]

      begin
        original_text = text_analysis[:original_text]
        logger.info("Rewriting text using speech patterns (#{original_text.length} chars, strategy: #{strategy})")
        start_time = Time.now

        # Select rewriting strategy based on pattern analysis
        rewritten_result = case strategy.to_s
                           when 'rhythm'
                             rewrite_for_rhythm_patterns(text_analysis, rewrite_guidance, rewrite_options)
                           when 'stress'
                             rewrite_for_stress_patterns(text_analysis, rewrite_guidance, rewrite_options)
                           when 'intonation'
                             rewrite_for_intonation_patterns(text_analysis, rewrite_guidance, rewrite_options)
                           when 'hybrid'
                             rewrite_with_hybrid_strategy(text_analysis, rewrite_guidance, rewrite_options)
                           else
                             rewrite_with_comprehensive_strategy(text_analysis, rewrite_guidance, rewrite_options)
                           end

        # Apply iterative refinement if enabled
        if rewrite_options[:iterative_refinement]
          rewritten_result = apply_iterative_refinement(rewritten_result, rewrite_guidance, rewrite_options)
        end

        # Validate meaning preservation
        if rewrite_options[:preserve_meaning] && !validate_meaning_preservation(original_text, rewritten_result[:rewritten_text],
                                                                                rewrite_options[:meaning_threshold])
          logger.warn('Rewritten text failed meaning preservation check, reverting to original')
          return create_fallback_result(text_analysis, rewrite_guidance)
        end

        rewrite_time = Time.now - start_time
        logger.info("Speech pattern rewriting completed in #{rewrite_time.round(2)}s")

        # Enhance result with analysis metadata
        enhance_rewrite_result(rewritten_result, text_analysis, rewrite_guidance, rewrite_time, strategy)
      rescue StandardError => e
        error_msg = "Speech pattern rewriting failed: #{e.message}"
        logger.error(error_msg)
        logger.debug("Backtrace: #{e.backtrace.join("\n")}")
        raise error_msg
      end
    end

    # Generate speech-pattern-informed prompts for LLM rewriting
    #
    # @param text_analysis [Hash] structured text analysis
    # @param rewrite_guidance [Hash] pattern-based guidance
    # @param strategy [String] rewriting strategy
    # @return [Hash] system and user prompts
    def generate_pattern_informed_prompts(text_analysis, rewrite_guidance, strategy)
      system_prompt = build_pattern_informed_system_prompt(strategy, rewrite_guidance)
      user_prompt = build_pattern_informed_user_prompt(text_analysis, rewrite_guidance, strategy)

      {
        system: system_prompt,
        user: user_prompt,
        strategy: strategy,
        guidance_summary: summarize_guidance(rewrite_guidance)
      }
    end

    private

    # Default rewriter options
    #
    # @return [Hash] default configuration
    def default_options
      {
        rewrite_strategy: 'hybrid',
        preserve_meaning: true,
        meaning_threshold: 0.85,
        detailed_logging: true,
        max_iterations: 3,
        iterative_refinement: true,
        timeout: 120
      }
    end

    # Validate rewrite inputs
    #
    # @param text_analysis [Hash] text analysis data
    # @param rewrite_guidance [Hash] guidance data
    # @raise [ArgumentError] if inputs are invalid
    def validate_rewrite_inputs(text_analysis, rewrite_guidance)
      unless text_analysis.is_a?(Hash) && text_analysis[:original_text]
        raise ArgumentError, 'Text analysis must be a hash with :original_text key'
      end

      unless rewrite_guidance.is_a?(Hash) && rewrite_guidance[:overall_strategy]
        raise ArgumentError, 'Rewrite guidance must be a hash with :overall_strategy key'
      end

      text = text_analysis[:original_text]
      return unless text.nil? || text.strip.empty?

      raise ArgumentError, 'Original text in analysis cannot be nil or empty'
    end

    # Rewrite text focusing on rhythm patterns
    #
    # @param text_analysis [Hash] text analysis data
    # @param rewrite_guidance [Hash] guidance data
    # @param options [Hash] rewrite options
    # @return [Hash] rewriting result
    def rewrite_for_rhythm_patterns(text_analysis, rewrite_guidance, options)
      logger.debug('Applying rhythm-focused rewriting strategy')

      rhythm_guidance = rewrite_guidance[:rhythm_adjustments]
      prompts = generate_rhythm_focused_prompts(text_analysis, rhythm_guidance)

      execute_llm_rewrite(prompts, options)
    end

    # Rewrite text focusing on stress patterns
    #
    # @param text_analysis [Hash] text analysis data
    # @param rewrite_guidance [Hash] guidance data
    # @param options [Hash] rewrite options
    # @return [Hash] rewriting result
    def rewrite_for_stress_patterns(text_analysis, rewrite_guidance, options)
      logger.debug('Applying stress-focused rewriting strategy')

      stress_guidance = rewrite_guidance[:stress_adjustments]
      prompts = generate_stress_focused_prompts(text_analysis, stress_guidance)

      execute_llm_rewrite(prompts, options)
    end

    # Rewrite text focusing on intonation patterns
    #
    # @param text_analysis [Hash] text analysis data
    # @param rewrite_guidance [Hash] guidance data
    # @param options [Hash] rewrite options
    # @return [Hash] rewriting result
    def rewrite_for_intonation_patterns(text_analysis, rewrite_guidance, options)
      logger.debug('Applying intonation-focused rewriting strategy')

      intonation_guidance = rewrite_guidance[:intonation_guidance]

      if intonation_guidance[:available]
        prompts = generate_intonation_focused_prompts(text_analysis, intonation_guidance)
        execute_llm_rewrite(prompts, options)
      else
        logger.warn('Intonation guidance not available, falling back to rhythm strategy')
        rewrite_for_rhythm_patterns(text_analysis, rewrite_guidance, options)
      end
    end

    # Rewrite text using hybrid strategy combining multiple pattern types
    #
    # @param text_analysis [Hash] text analysis data
    # @param rewrite_guidance [Hash] guidance data
    # @param options [Hash] rewrite options
    # @return [Hash] rewriting result
    def rewrite_with_hybrid_strategy(text_analysis, rewrite_guidance, options)
      logger.debug('Applying hybrid rewriting strategy')

      prompts = generate_hybrid_prompts(text_analysis, rewrite_guidance)
      execute_llm_rewrite(prompts, options)
    end

    # Rewrite text using comprehensive strategy considering all patterns
    #
    # @param text_analysis [Hash] text analysis data
    # @param rewrite_guidance [Hash] guidance data
    # @param options [Hash] rewrite options
    # @return [Hash] rewriting result
    def rewrite_with_comprehensive_strategy(text_analysis, rewrite_guidance, options)
      logger.debug('Applying comprehensive rewriting strategy')

      prompts = generate_comprehensive_prompts(text_analysis, rewrite_guidance)
      execute_llm_rewrite(prompts, options)
    end

    # Execute LLM-based text rewriting
    #
    # @param prompts [Hash] system and user prompts
    # @param options [Hash] execution options
    # @return [Hash] rewriting result
    def execute_llm_rewrite(prompts, options)
      logger.debug("Executing LLM rewrite with #{prompts[:strategy]} strategy")

      # Make LLM request for rewriting
      response = Timeout.timeout(options[:timeout]) do
        full_prompt = "#{prompts[:system]}\n\n#{prompts[:user]}"
        @llm_converter.instance_variable_get(:@client).with_model(@llm_converter.model).with_temperature(0.4).ask(full_prompt)
      end

      # Extract rewritten text
      rewritten_text = extract_rewritten_text(response)

      # Re-analyze the rewritten text
      rewritten_analysis = @text_analyzer.analyze(rewritten_text)

      {
        rewritten_text: rewritten_text,
        rewritten_analysis: rewritten_analysis,
        prompts_used: prompts,
        llm_response: response
      }
    rescue Timeout::Error
      error_msg = "LLM rewrite timed out after #{options[:timeout]} seconds"
      logger.error(error_msg)
      raise error_msg
    rescue StandardError => e
      error_msg = "LLM rewrite execution failed: #{e.message}"
      logger.error(error_msg)
      raise error_msg
    end

    # Apply iterative refinement to improve rewriting results
    #
    # @param initial_result [Hash] initial rewriting result
    # @param rewrite_guidance [Hash] guidance data
    # @param options [Hash] refinement options
    # @return [Hash] refined rewriting result
    def apply_iterative_refinement(initial_result, rewrite_guidance, options)
      max_iterations = options[:max_iterations] || 3
      current_result = initial_result
      iteration = 1

      while iteration <= max_iterations
        logger.debug("Applying iterative refinement iteration #{iteration}/#{max_iterations}")

        # Analyze current result against guidance
        refinement_needed = assess_refinement_needs(current_result, rewrite_guidance)

        if refinement_needed.empty?
          logger.debug("No further refinement needed after #{iteration - 1} iterations")
          break
        end

        # Generate refinement prompts
        refinement_prompts = generate_refinement_prompts(current_result, refinement_needed, rewrite_guidance)

        # Apply refinement
        refined_result = execute_llm_rewrite(refinement_prompts, options)

        # Update current result if improvement detected
        if assess_improvement(current_result, refined_result, rewrite_guidance)
          current_result = refined_result
          current_result[:refinement_iterations] = iteration
        else
          logger.debug("No improvement detected in iteration #{iteration}, stopping refinement")
          break
        end

        iteration += 1
      end

      current_result[:total_refinement_iterations] = iteration - 1
      current_result
    end

    # Extract rewritten text from LLM response
    #
    # @param response [String, Hash, RubyLLM::Message] LLM response
    # @return [String] extracted rewritten text
    def extract_rewritten_text(response)
      # Handle different response types
      content = case response
                when String
                  response
                when RubyLLM::Message
                  response.content || response.to_s
                else
                  response.dig('content') || response.dig('message', 'content') || response.to_s
                end

      raise "No content found in LLM response: #{response.inspect}" if content.nil? || content.strip.empty?

      # Clean up any markdown formatting
      content = content.strip
      content = content.gsub(/^```(?:text)?\s*\n?/, '').gsub(/\n?```\s*$/, '')
      content.strip
    end

    # Validate meaning preservation between original and rewritten text
    #
    # @param original [String] original text
    # @param rewritten [String] rewritten text
    # @param threshold [Float] minimum similarity threshold
    # @return [Boolean] true if meaning is preserved
    def validate_meaning_preservation(original, rewritten, threshold)
      # Enhanced meaning preservation check

      # Length similarity check
      length_ratio = [original.length, rewritten.length].min.to_f / [original.length, rewritten.length].max
      return false if length_ratio < 0.4

      # Content word preservation check
      original_words = extract_content_words(original)
      rewritten_words = extract_content_words(rewritten)

      return true if original_words.empty?

      # Calculate content overlap
      overlap = (original_words & rewritten_words).length
      content_preservation = overlap.to_f / original_words.length

      # Structural similarity check
      structural_similarity = assess_structural_similarity(original, rewritten)

      # Combined score
      combined_score = (content_preservation * 0.6) + (structural_similarity * 0.2) + (length_ratio * 0.2)

      logger.debug("Meaning preservation: content=#{content_preservation.round(2)}, " \
                  "structure=#{structural_similarity.round(2)}, " \
                  "length=#{length_ratio.round(2)}, " \
                  "combined=#{combined_score.round(2)}")

      combined_score >= threshold
    end

    # Extract content words from text
    #
    # @param text [String] input text
    # @return [Array<String>] content words
    def extract_content_words(text)
      words = text.downcase.gsub(/[^\w\s]/, '').split
      function_words = %w[the a an and or but in on at to for of with by from that this these those is are was were be
                          been have has had do does did will would could should may might can cannot]
      words - function_words
    end

    # Assess structural similarity between texts
    #
    # @param text1 [String] first text
    # @param text2 [String] second text
    # @return [Float] structural similarity score (0.0-1.0)
    def assess_structural_similarity(text1, text2)
      # Compare sentence structures
      sentences1 = text1.split(/[.!?]+/).map(&:strip).reject(&:empty?)
      sentences2 = text2.split(/[.!?]+/).map(&:strip).reject(&:empty?)

      # Sentence count similarity
      count_similarity = [sentences1.length, sentences2.length].min.to_f / [sentences1.length, sentences2.length].max

      # Average sentence length similarity
      avg_len1 = sentences1.map(&:length).sum / sentences1.length.to_f
      avg_len2 = sentences2.map(&:length).sum / sentences2.length.to_f
      length_similarity = [avg_len1, avg_len2].min / [avg_len1, avg_len2].max

      (count_similarity + length_similarity) / 2.0
    end

    # Create fallback result when rewriting fails validation
    #
    # @param text_analysis [Hash] original text analysis
    # @param rewrite_guidance [Hash] guidance data
    # @return [Hash] fallback result
    def create_fallback_result(text_analysis, rewrite_guidance)
      {
        rewritten_text: text_analysis[:original_text],
        rewritten_analysis: text_analysis,
        rewrite_applied: false,
        fallback_reason: 'meaning_preservation_failed',
        guidance_applied: rewrite_guidance[:overall_strategy]
      }
    end

    # Enhance rewrite result with additional metadata
    #
    # @param result [Hash] basic rewrite result
    # @param text_analysis [Hash] original text analysis
    # @param rewrite_guidance [Hash] guidance data
    # @param rewrite_time [Float] processing time
    # @param strategy [String] strategy used
    # @return [Hash] enhanced result
    def enhance_rewrite_result(result, text_analysis, rewrite_guidance, rewrite_time, strategy)
      result.merge({
                     original_text: text_analysis[:original_text],
                     original_analysis: text_analysis,
                     rewrite_applied: true,
                     strategy_used: strategy,
                     guidance_applied: rewrite_guidance[:overall_strategy],
                     processing_time: rewrite_time,
                     changes_summary: analyze_changes(text_analysis[:original_text], result[:rewritten_text]),
                     pattern_alignment: assess_pattern_alignment(result, rewrite_guidance)
                   })
    end

    # Analyze changes between original and rewritten text
    #
    # @param original [String] original text
    # @param rewritten [String] rewritten text
    # @return [Hash] summary of changes
    def analyze_changes(original, rewritten)
      {
        length_change: rewritten.length - original.length,
        word_count_change: rewritten.split.length - original.split.length,
        sentence_count_change: rewritten.split(/[.!?]+/).length - original.split(/[.!?]+/).length,
        structural_changes: identify_structural_changes(original, rewritten)
      }
    end

    # Identify structural changes between texts
    #
    # @param original [String] original text
    # @param rewritten [String] rewritten text
    # @return [Array<String>] list of structural changes
    def identify_structural_changes(original, rewritten)
      changes = []

      orig_sentences = original.split(/[.!?]+/).map(&:strip).reject(&:empty?)
      rewr_sentences = rewritten.split(/[.!?]+/).map(&:strip).reject(&:empty?)

      if rewr_sentences.length > orig_sentences.length
        changes << 'sentence_splitting'
      elsif rewr_sentences.length < orig_sentences.length
        changes << 'sentence_combining'
      end

      # Check for word order changes (simplified)
      orig_words = original.downcase.gsub(/[^\w\s]/, '').split
      rewr_words = rewritten.downcase.gsub(/[^\w\s]/, '').split

      changes << 'word_substitution' if (orig_words - rewr_words).any?

      changes << 'word_count_adjustment' if orig_words.length != rewr_words.length

      changes
    end

    # Assess how well the rewritten text aligns with pattern guidance
    #
    # @param result [Hash] rewrite result
    # @param guidance [Hash] guidance data
    # @return [Hash] alignment assessment
    def assess_pattern_alignment(result, guidance)
      rewritten_analysis = result[:rewritten_analysis]
      target_strategy = guidance[:overall_strategy]

      {
        strategy_alignment: assess_strategy_alignment(rewritten_analysis, target_strategy),
        rhythm_alignment: assess_rhythm_alignment(rewritten_analysis, guidance[:rhythm_adjustments]),
        stress_alignment: assess_stress_alignment(rewritten_analysis, guidance[:stress_adjustments]),
        overall_score: calculate_overall_alignment_score(rewritten_analysis, guidance)
      }
    end

    # Generate prompts for different rewriting strategies

    def build_pattern_informed_system_prompt(strategy, guidance)
      base_prompt = <<~SYSTEM
        You are an expert in speech pattern analysis and text rewriting for optimal prosodic matching.
        Your task is to rewrite text to better match specific speech patterns extracted from audio analysis
        while preserving the original meaning and communicative intent.

        Key Principles:
        1. Maintain semantic content and pragmatic force
        2. Optimize text structure for natural speech rhythm
        3. Consider prosodic boundaries and stress patterns
        4. Preserve register and stylistic consistency
        5. Apply linguistic modifications that enhance speech naturalness
      SYSTEM

      strategy_specific = case strategy.to_s
                          when 'rhythm'
                            "\nFocus: Optimize text for rhythm and timing patterns extracted from speech analysis."
                          when 'stress'
                            "\nFocus: Adjust text structure to match stress patterns and emphasis."
                          when 'intonation'
                            "\nFocus: Modify text to support target intonation contours and pitch patterns."
                          when 'hybrid'
                            "\nFocus: Balance rhythm, stress, and intonation considerations."
                          else
                            "\nFocus: Comprehensive optimization for all detected speech patterns."
                          end

      "#{base_prompt}#{strategy_specific}"
    end

    def build_pattern_informed_user_prompt(text_analysis, guidance, strategy)
      original_text = text_analysis[:original_text]
      overall_strategy = guidance[:overall_strategy]

      base_prompt = <<~PROMPT
        Rewrite this text to match the extracted speech patterns while preserving meaning.

        ORIGINAL TEXT:
        #{original_text}

        SPEECH PATTERN ANALYSIS:
        Primary Focus: #{overall_strategy[:primary_focus]}
        Rewrite Aggressiveness: #{overall_strategy[:rewrite_aggressiveness]}

      PROMPT

      # Add strategy-specific guidance
      strategy_guidance = case strategy.to_s
                          when 'rhythm'
                            build_rhythm_guidance_section(guidance[:rhythm_adjustments])
                          when 'stress'
                            build_stress_guidance_section(guidance[:stress_adjustments])
                          when 'intonation'
                            build_intonation_guidance_section(guidance[:intonation_guidance])
                          when 'hybrid'
                            build_hybrid_guidance_section(guidance)
                          else
                            build_comprehensive_guidance_section(guidance)
                          end

      requirements = <<~REQUIREMENTS

        REWRITING REQUIREMENTS:
        1. Preserve all semantic content and communicative function
        2. Maintain original register, style, and tone
        3. Apply the specified speech pattern optimizations
        4. Ensure natural language flow and readability
        5. Return ONLY the rewritten text, no explanations or markup

        Focus on making changes that will improve prosodic naturalness when spoken aloud.
      REQUIREMENTS

      "#{base_prompt}#{strategy_guidance}#{requirements}"
    end

    def generate_rhythm_focused_prompts(text_analysis, rhythm_guidance)
      system_prompt = build_pattern_informed_system_prompt('rhythm', { rhythm_adjustments: rhythm_guidance })
      user_prompt = build_rhythm_specific_user_prompt(text_analysis, rhythm_guidance)

      { system: system_prompt, user: user_prompt, strategy: 'rhythm' }
    end

    def generate_stress_focused_prompts(text_analysis, stress_guidance)
      system_prompt = build_pattern_informed_system_prompt('stress', { stress_adjustments: stress_guidance })
      user_prompt = build_stress_specific_user_prompt(text_analysis, stress_guidance)

      { system: system_prompt, user: user_prompt, strategy: 'stress' }
    end

    def generate_intonation_focused_prompts(text_analysis, intonation_guidance)
      system_prompt = build_pattern_informed_system_prompt('intonation', { intonation_guidance: intonation_guidance })
      user_prompt = build_intonation_specific_user_prompt(text_analysis, intonation_guidance)

      { system: system_prompt, user: user_prompt, strategy: 'intonation' }
    end

    def generate_hybrid_prompts(text_analysis, guidance)
      system_prompt = build_pattern_informed_system_prompt('hybrid', guidance)
      user_prompt = build_pattern_informed_user_prompt(text_analysis, guidance, 'hybrid')

      { system: system_prompt, user: user_prompt, strategy: 'hybrid' }
    end

    def generate_comprehensive_prompts(text_analysis, guidance)
      system_prompt = build_pattern_informed_system_prompt('comprehensive', guidance)
      user_prompt = build_pattern_informed_user_prompt(text_analysis, guidance, 'comprehensive')

      { system: system_prompt, user: user_prompt, strategy: 'comprehensive' }
    end

    # Build guidance sections for different strategies

    def build_rhythm_guidance_section(rhythm_adjustments)
      return '' unless rhythm_adjustments

      <<~RHYTHM
        RHYTHM PATTERN TARGETS:
        - Target Tempo: #{rhythm_adjustments[:target_tempo]} BPM
        - Rhythm Type: #{rhythm_adjustments[:rhythm_type]}
        - Apply rhythm-based sentence segmentation
        - Optimize for regular timing intervals

      RHYTHM
    end

    def build_stress_guidance_section(stress_adjustments)
      return '' unless stress_adjustments

      <<~STRESS
        STRESS PATTERN TARGETS:
        - Stress Pattern: #{stress_adjustments[:stress_pattern]}
        - Stress Density: #{stress_adjustments[:stress_density]}
        - Focus on content word emphasis
        - Balance stressed and unstressed syllables

      STRESS
    end

    def build_intonation_guidance_section(intonation_guidance)
      return '' unless intonation_guidance[:available]

      <<~INTONATION
        INTONATION PATTERN TARGETS:
        - Contour Shape: #{intonation_guidance[:contour_shape]}
        - Boundary Tones: #{intonation_guidance[:boundary_tones]}
        - Support target pitch movements
        - Optimize for phrase-level intonation

      INTONATION
    end

    def build_hybrid_guidance_section(guidance)
      rhythm_section = build_rhythm_guidance_section(guidance[:rhythm_adjustments])
      stress_section = build_stress_guidance_section(guidance[:stress_adjustments])

      "#{rhythm_section}#{stress_section}INTEGRATION: Balance rhythm and stress considerations.\n"
    end

    def build_comprehensive_guidance_section(guidance)
      sections = []
      sections << build_rhythm_guidance_section(guidance[:rhythm_adjustments])
      sections << build_stress_guidance_section(guidance[:stress_adjustments])
      sections << build_intonation_guidance_section(guidance[:intonation_guidance])

      sections.join + "INTEGRATION: Optimize for all speech pattern dimensions.\n"
    end

    # Specific prompt builders for focused strategies

    def build_rhythm_specific_user_prompt(text_analysis, rhythm_guidance)
      original_text = text_analysis[:original_text]
      target_tempo = rhythm_guidance[:target_tempo] || 120

      <<~PROMPT
        Rewrite this text to optimize for rhythm and timing:

        ORIGINAL TEXT:
        #{original_text}

        RHYTHM TARGETS:
        - Target speaking tempo: #{target_tempo} BPM
        - Rhythm regularity: #{rhythm_guidance[:rhythm_type]}
        - Optimize clause boundaries for rhythmic flow
        - Consider syllable timing and word stress placement

        Apply rhythm-focused modifications:
        1. Adjust sentence length for target tempo
        2. Break long sentences at natural rhythmic boundaries
        3. Use coordination and subordination for rhythmic variety
        4. Balance syllable distribution across phrases

        Return only the rewritten text that optimizes rhythmic flow.
      PROMPT
    end

    def build_stress_specific_user_prompt(text_analysis, stress_guidance)
      original_text = text_analysis[:original_text]
      stress_pattern = stress_guidance[:stress_pattern] || 'balanced'

      <<~PROMPT
        Rewrite this text to optimize for stress patterns:

        ORIGINAL TEXT:
        #{original_text}

        STRESS TARGETS:
        - Target stress pattern: #{stress_pattern}
        - Stress density: #{stress_guidance[:stress_density]}
        - Focus on content word prominence
        - Balance stressed and unstressed elements

        Apply stress-focused modifications:
        1. Choose words that fit target stress patterns
        2. Adjust word order to optimize stress placement
        3. Use function words to manage stress density
        4. Consider syllable weight in word selection

        Return only the rewritten text that optimizes stress patterns.
      PROMPT
    end

    def build_intonation_specific_user_prompt(text_analysis, intonation_guidance)
      original_text = text_analysis[:original_text]
      contour_shape = intonation_guidance[:contour_shape] || 'neutral'

      <<~PROMPT
        Rewrite this text to optimize for intonation patterns:

        ORIGINAL TEXT:
        #{original_text}

        INTONATION TARGETS:
        - Target contour shape: #{contour_shape}
        - Boundary tones: #{intonation_guidance[:boundary_tones]}
        - Support natural pitch movement
        - Optimize phrase-level prosody

        Apply intonation-focused modifications:
        1. Structure sentences to support target pitch contours
        2. Use clause types that match intonation patterns
        3. Position focus elements for optimal pitch prominence
        4. Consider question/statement patterns

        Return only the rewritten text that optimizes intonation flow.
      PROMPT
    end

    # Assessment methods for iterative refinement

    def assess_refinement_needs(result, guidance)
      needs = []
      rewritten_analysis = result[:rewritten_analysis]

      # Check if further rhythm optimization needed
      if guidance[:rhythm_adjustments] && !rhythm_optimized?(rewritten_analysis, guidance[:rhythm_adjustments])
        needs << 'rhythm_refinement'
      end

      # Check if stress patterns need adjustment
      if guidance[:stress_adjustments] && !stress_optimized?(rewritten_analysis, guidance[:stress_adjustments])
        needs << 'stress_refinement'
      end

      # Check sentence length distribution
      needs << 'sentence_balance' if uneven_sentence_distribution?(rewritten_analysis)

      needs
    end

    def generate_refinement_prompts(current_result, refinement_needs, guidance)
      current_text = current_result[:rewritten_text]

      system_prompt = <<~SYSTEM
        You are refining a text rewrite to better match speech patterns.
        Focus on the specific aspects that need improvement while maintaining meaning.
      SYSTEM

      user_prompt = <<~PROMPT
        Refine this text to improve the following aspects: #{refinement_needs.join(', ')}

        CURRENT TEXT:
        #{current_text}

        REFINEMENT TARGETS:
        #{build_refinement_targets(refinement_needs, guidance)}

        Make minimal changes focused only on the identified refinement needs.
        Return only the refined text.
      PROMPT

      { system: system_prompt, user: user_prompt, strategy: 'refinement' }
    end

    def build_refinement_targets(needs, guidance)
      targets = []

      targets << '- Improve rhythmic flow and timing' if needs.include?('rhythm_refinement')

      targets << '- Better stress pattern alignment' if needs.include?('stress_refinement')

      targets << '- More balanced sentence length distribution' if needs.include?('sentence_balance')

      targets.join("\n")
    end

    def assess_improvement(old_result, new_result, guidance)
      # Simple improvement assessment - could be more sophisticated
      old_score = calculate_overall_alignment_score(old_result[:rewritten_analysis], guidance)
      new_score = calculate_overall_alignment_score(new_result[:rewritten_analysis], guidance)

      new_score > old_score
    end

    # Pattern assessment helper methods

    def rhythm_optimized?(analysis, rhythm_guidance)
      # Simplified rhythm assessment
      sentences = analysis[:sentences] || []
      return true if sentences.empty?

      avg_length = sentences.map { |s| s[:word_count] }.sum / sentences.length.to_f
      target_length = (rhythm_guidance[:target_tempo] || 120) / 60.0 * 4 # Rough estimate

      (avg_length - target_length).abs < 2
    end

    def stress_optimized?(analysis, stress_guidance)
      # Simplified stress assessment
      true # Placeholder - would analyze stress distribution
    end

    def uneven_sentence_distribution?(analysis)
      sentences = analysis[:sentences] || []
      return false if sentences.length < 3

      lengths = sentences.map { |s| s[:word_count] }
      variance = calculate_variance(lengths)
      variance > 3.0 # Threshold for unevenness
    end

    def calculate_variance(values)
      return 0 if values.empty?

      mean = values.sum / values.length.to_f
      variance = values.map { |v| (v - mean)**2 }.sum / values.length.to_f
      Math.sqrt(variance)
    end

    # Alignment assessment methods

    def assess_strategy_alignment(analysis, strategy)
      # Assess how well the rewritten text aligns with the target strategy
      case strategy[:primary_focus]
      when 'rhythm'
        assess_rhythm_alignment(analysis, strategy)
      when 'stress'
        assess_stress_alignment(analysis, strategy)
      when 'intonation'
        assess_intonation_alignment(analysis, strategy)
      else
        0.7 # Default moderate alignment
      end
    end

    def assess_rhythm_alignment(analysis, rhythm_guidance)
      return 0.5 unless rhythm_guidance

      sentences = analysis[:sentences] || []
      return 0.5 if sentences.empty?

      # Simple rhythm alignment based on sentence regularity
      lengths = sentences.map { |s| s[:word_count] }
      variance = calculate_variance(lengths)

      # Lower variance = better rhythm alignment
      [1.0 - (variance / 5.0), 0.0].max
    end

    def assess_stress_alignment(analysis, stress_guidance)
      return 0.5 unless stress_guidance

      # Placeholder stress alignment assessment
      0.7
    end

    def assess_intonation_alignment(analysis, intonation_guidance)
      return 0.5 unless intonation_guidance[:available]

      # Placeholder intonation alignment assessment
      0.6
    end

    def calculate_overall_alignment_score(analysis, guidance)
      rhythm_score = assess_rhythm_alignment(analysis, guidance[:rhythm_adjustments])
      stress_score = assess_stress_alignment(analysis, guidance[:stress_adjustments])

      # Weighted average based on guidance priorities
      weights = determine_alignment_weights(guidance[:overall_strategy])

      (rhythm_score * weights[:rhythm]) + (stress_score * weights[:stress])
    end

    def determine_alignment_weights(strategy)
      case strategy[:primary_focus]
      when 'rhythm'
        { rhythm: 0.8, stress: 0.2 }
      when 'stress'
        { rhythm: 0.2, stress: 0.8 }
      else
        { rhythm: 0.5, stress: 0.5 }
      end
    end

    def summarize_guidance(guidance)
      {
        primary_focus: guidance[:overall_strategy][:primary_focus],
        aggressiveness: guidance[:overall_strategy][:rewrite_aggressiveness],
        patterns_available: {
          rhythm: !guidance[:rhythm_adjustments].nil?,
          stress: !guidance[:stress_adjustments].nil?,
          intonation: guidance[:intonation_guidance][:available]
        }
      }
    end
  end
end
