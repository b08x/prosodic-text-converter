# frozen_string_literal: true

# Test helpers and shared utilities for RSpec tests
module TestHelpers
  # Create a mock ProsodicPattern for testing
  def create_mock_pattern(name: 'test', segment_duration: 1.0, pause_duration: 0.35,
                          pitch_variation: 5, rate: 'medium')
    pattern = instance_double(ProsodicTextConverter::ProsodicPattern)
    allow(pattern).to receive(:name).and_return(name)
    allow(pattern).to receive(:segment_duration).and_return(segment_duration)
    allow(pattern).to receive(:pause_duration).and_return(pause_duration)
    allow(pattern).to receive(:pitch_variation).and_return(pitch_variation)
    allow(pattern).to receive(:rate).and_return(rate)
    allow(pattern).to receive(:to_h).and_return({
                                                  name: name,
                                                  segment_duration: segment_duration,
                                                  pause_duration: pause_duration,
                                                  pitch_variation: pitch_variation,
                                                  rate: rate
                                                })
    pattern
  end

  # Create sample text analysis data
  def create_text_analysis(text: 'Hello world. This is a test.')
    {
      original_text: text,
      language: 'en',
      sentence_count: 2,
      sentences: [
        {
          index: 0,
          text: 'Hello world.',
          word_count: 2,
          words: [
            { text: 'Hello', syllable_count: 2 },
            { text: 'world', syllable_count: 1 }
          ],
          pause_indicators: ['.']
        },
        {
          index: 1,
          text: 'This is a test.',
          word_count: 4,
          words: [
            { text: 'This', syllable_count: 1 },
            { text: 'is', syllable_count: 1 },
            { text: 'a', syllable_count: 1 },
            { text: 'test', syllable_count: 1 }
          ],
          pause_indicators: ['.']
        }
      ]
    }
  end

  # Create sample pitch analysis data
  def create_pitch_data
    [
      { timestamp: 0.0, frequency: 150.0 },
      { timestamp: 0.1, frequency: 160.0 },
      { timestamp: 0.2, frequency: 140.0 },
      { timestamp: 0.3, frequency: 170.0 }
    ]
  end

  # Mock logger that captures messages
  def create_mock_logger
    logger = instance_double(Logger)
    allow(logger).to receive(:info)
    allow(logger).to receive(:debug)
    allow(logger).to receive(:error)
    allow(logger).to receive(:warn)
    logger
  end
end

RSpec.configure do |config|
  config.include TestHelpers
end
