#!/usr/bin/env ruby

require_relative 'lib/prosodic-text-converter/analysis/prosodic_pattern'

# Test the current word calculation logic
patterns = [
  { name: 'deliberate', duration: 1.0, rate: 'medium' },
  { name: 'rapid', duration: 0.6, rate: 'fast' },
  { name: 'contemplative', duration: 1.4, rate: 'slow' }
]

def optimal_words_per_chunk(segment_duration, rate)
  base_wpm = { 'slow' => 120, 'medium' => 150, 'fast' => 180 }[rate] || 150
  ((base_wpm / 60.0) * segment_duration).round
end

puts "Current word segmentation logic:"
puts "================================"
patterns.each do |p|
  words = optimal_words_per_chunk(p[:duration], p[:rate])
  puts "#{p[:name]}: #{p[:duration]}s at #{p[:rate]} rate = #{words} words per segment"
end

puts "\nExample text analysis:"
text = "Advanced Micro Devices (AMD) has unveiled new details about its next-generation AI chips. The Instinct MI400 series will ship next year. They can be assembled into full server racks with thousands of chips."
sentences = text.split(/[.!?]+/).map(&:strip).reject(&:empty?)

puts "Text: #{text}"
puts "Sentences: #{sentences.length}"
sentences.each_with_index do |sentence, idx|
  words = sentence.split(' ').length
  puts "  Sentence #{idx + 1}: #{words} words - '#{sentence}'"
end

puts "\nCurrent segmentation (sentence-based):"
puts "======================================"
sentences.each_with_index do |sentence, idx|
  words = sentence.split(' ').length
  puts "Segment #{idx + 1}: #{words} words"
  puts "  SSML: <prosody>#{sentence}</prosody>"
end

puts "\nProblem: Each sentence becomes a separate segment with breaks between them."
puts "This creates choppy speech instead of flowing prose."
puts "\nSolution: Group sentences into longer segments based on:"
puts "1. Target words per segment (currently calculated correctly)"
puts "2. Natural linguistic boundaries (clauses, phrases)"
puts "3. Semantic coherence"