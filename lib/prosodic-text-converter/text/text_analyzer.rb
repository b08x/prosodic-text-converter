# frozen_string_literal: true

require 'pragmatic_tokenizer'
require_relative '../analysis/prosodic_pattern'

module ProsodicTextConverter
  # Text analysis and chunking
  class TextAnalyzer
    def initialize(pattern)
      @pattern = pattern
      @tokenizer = PragmaticTokenizer::Tokenizer.new
    end

    def chunk_text(text)
      sentences = @tokenizer.segment(text)
      chunks = []
      
      sentences.each do |sentence|
        words = @tokenizer.tokenize(sentence)
        sentence_chunks = words.each_slice(optimal_chunk_size).map(&:join)
        chunks.concat(sentence_chunks)
      end
      
      chunks
    end

    private

    def optimal_chunk_size
      # Calculate words per chunk based on segment duration
      # Assuming ~150 words per minute average speech rate
      base_wpm = case @pattern.rate
                when 'slow' then 120
                when 'medium' then 150
                when 'fast' then 180
                else 150
                end
      
      words_per_second = base_wpm / 60.0
      (words_per_second * @pattern.segment_duration).round.clamp(3, 8)
    end
  end
end