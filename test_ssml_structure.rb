#!/usr/bin/env ruby

require_relative 'lib/prosodic-text-converter/analysis/prosodic_pattern'

# Create a simple pattern 
pattern = ProsodicTextConverter::ProsodicPattern.new(
  name: 'test',
  segment_duration: 1.0,
  pause_duration: 0.35,
  pitch_variation: 5,
  rate: 'medium'
)

# Mock text analyzer
class MockTextAnalyzer
  def analyze(text)
    sentences = text.split(/[.!?]+/).map(&:strip).reject(&:empty?)
    {
      original_text: text,
      language: :en,
      sentence_count: sentences.length,
      sentences: sentences.map.with_index do |sentence, index|
        words = sentence.split(' ')
        {
          index: index,
          text: sentence,
          word_count: words.length,
          words: words.map { |word| { text: word, syllable_count: 2 } },
          pause_indicators: ['.']
        }
      end
    }
  end
end

# Mock LLM converter to show what prompts are being sent
class MockLLMConverter
  def initialize(*args)
  end
  
  def convert_text_with_analysis(text_analysis, pattern)
    puts "PROMPT WOULD BE:"
    puts "================="
    
    # Simulate the actual prompt building
    text = text_analysis[:original_text]
    sentences = text_analysis[:sentences]
    
    sentence_summary = sentences.map do |sent|
      pause_hints = sent[:pause_indicators].join(', ') if sent[:pause_indicators].any?
      syllables = sent[:words].sum { |w| w[:syllable_count] }
      "Sentence #{sent[:index] + 1}: #{sent[:word_count]} words, #{syllables} syllables" +
        (pause_hints ? " (#{pause_hints})" : '')
    end.join("\n")
    
    puts "TEXT: #{text}"
    puts "SENTENCES: #{text_analysis[:sentence_count]}"
    puts sentence_summary
    puts "PATTERN: #{pattern.segment_duration}s segments, #{(pattern.pause_duration * 1000).to_i}ms pauses"
    puts "================="
    
    # Return mock SSML that shows current structure
    ssml_parts = sentences.map.with_index do |sent, idx|
      pitch_var = idx.even? ? '+2%' : '-1%'
      "<prosody rate=\"#{pattern.rate}\" pitch=\"#{pitch_var}\">#{sent[:text]}</prosody>"
    end
    
    break_tag = "<break time=\"#{(pattern.pause_duration * 1000).to_i}ms\"/>"
    "<speak>\n#{ssml_parts.join("\n#{break_tag}\n")}\n</speak>"
  end
end

# Test text
text = "Advanced Micro Devices (AMD) has unveiled new details about its next-generation AI chips. The Instinct MI400 series will ship next year. They can be assembled into full server racks with thousands of chips."

# Create mock analyzer and converter
analyzer = MockTextAnalyzer.new
converter = MockLLMConverter.new

# Analyze text
analysis = analyzer.analyze(text)

# Show the analysis
puts "TEXT ANALYSIS:"
puts "=============="
puts "Original: #{analysis[:original_text]}"
puts "Sentences: #{analysis[:sentence_count]}"
analysis[:sentences].each do |sent|
  puts "  Sentence #{sent[:index] + 1}: '#{sent[:text]}' (#{sent[:word_count]} words)"
end
puts

# Generate mock SSML
ssml = converter.convert_text_with_analysis(analysis, pattern)
puts "GENERATED SSML:"
puts "==============="
puts ssml