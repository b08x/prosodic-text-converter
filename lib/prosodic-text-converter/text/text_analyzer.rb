# frozen_string_literal: true

require 'lingua'
require 'pragmatic_tokenizer'
require_relative '../core/logging'

module ProsodicTextConverter
  # Text preprocessing and basic segmentation
  # Provides clean, structured text input for LLM prosodic analysis
  class TextAnalyzer
    include Logging
    # Initialize the text analyzer
    #
    # @param language [Symbol] language code for lingua (default: :en)
    def initialize(language: :en)
      @language = language
      @tokenizer = PragmaticTokenizer::Tokenizer.new(
        language: language,
        clean: true,
        punctuation: :all
      )
    end

    # Analyze text and return structured data for LLM processing
    #
    # @param text [String] input text to analyze
    # @return [Hash] structured text data with sentences, words, and metadata
    def analyze(text)
      sentences = segment_sentences(text)

      {
        original_text: text,
        language: @language,
        sentence_count: sentences.length,
        sentences: sentences.map.with_index do |sentence, index|
          analyze_sentence(sentence, index)
        end
      }
    end

    private

    # Segment text into sentences using lingua
    #
    # @param text [String] input text
    # @return [Array<String>] array of sentences
    def segment_sentences(text)
      # Use lingua for proper sentence boundary detection
      case @language
      when :en
        Lingua::EN::Sentence.sentences(text)
      else
        # Fallback to basic sentence splitting if language not supported
        text.split(/[.!?]+/).map(&:strip).reject(&:empty?)
      end
    end

    # Analyze individual sentence structure
    #
    # @param sentence [String] sentence text
    # @param index [Integer] sentence position in text
    # @return [Hash] sentence analysis data
    def analyze_sentence(sentence, index)
      words = @tokenizer.tokenize(sentence)

      {
        index: index,
        text: sentence.strip,
        word_count: words.length,
        words: words.map { |word| analyze_word(word) },
        punctuation: extract_punctuation(sentence),
        pause_indicators: detect_pause_indicators(sentence)
      }
    end

    # Analyze individual word properties
    #
    # @param word [String] word to analyze
    # @return [Hash] word analysis data
    def analyze_word(word)
      {
        text: word,
        syllable_count: count_syllables(word),
        length: word.length
      }
    end

    # Count syllables in a word using lingua
    #
    # @param word [String] word to count syllables for
    # @return [Integer] syllable count
    def count_syllables(word)
      case @language
      when :en
        Lingua::EN::Syllable.syllables(word.downcase.gsub(/[^a-z]/, ''))
      else
        # Fallback: rough estimate based on vowel groups
        word.downcase.scan(/[aeiouy]+/).length.clamp(1, Float::INFINITY)
      end
    end

    # Extract punctuation marks that indicate prosodic boundaries
    #
    # @param sentence [String] sentence text
    # @return [Array<Hash>] punctuation marks with positions and types
    def extract_punctuation(sentence)
      punctuation_marks = []
      sentence.scan(/[.!?,:;—–-]/).each_with_index do |mark, pos|
        punctuation_marks << {
          mark: mark,
          position: pos,
          pause_type: classify_pause(mark)
        }
      end
      punctuation_marks
    end

    # Detect textual indicators that suggest prosodic boundaries
    #
    # @param sentence [String] sentence text
    # @return [Array<String>] pause indicator types found
    def detect_pause_indicators(sentence)
      indicators = []

      # Coordinating conjunctions (and, but, or)
      indicators << 'conjunction' if sentence.match?(/\b(and|but|or|yet|so)\b/i)

      # Subordinating conjunctions (because, although, when)
      indicators << 'subordination' if sentence.match?(/\b(because|although|when|while|if|since)\b/i)

      # Discourse markers (however, therefore, meanwhile)
      indicators << 'discourse_marker' if sentence.match?(/\b(however|therefore|meanwhile|furthermore|moreover)\b/i)

      # Parenthetical expressions
      indicators << 'parenthetical' if sentence.match?(/\([^)]+\)/)

      indicators.uniq
    end

    # Classify punctuation marks by their typical pause duration
    #
    # @param mark [String] punctuation mark
    # @return [Symbol] pause classification
    def classify_pause(mark)
      case mark
      when '.', '!', '?'
        :full_stop
      when ';'
        :semi_pause
      when ':'
        :continuation
      when ','
        :brief_pause
      when '—', '–'
        :dash_pause
      when '-'
        :hyphen
      else
        :unknown
      end
    end
  end
end
