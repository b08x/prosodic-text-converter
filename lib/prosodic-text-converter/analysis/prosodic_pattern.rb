# frozen_string_literal: true

module ProsodicTextConverter
  # Prosodic pattern definition for speech synthesis timing and rhythm
  #
  # @example Creating a custom pattern
  #   pattern = ProsodicPattern.new(
  #     name: 'conversational',
  #     segment_duration: 1.2,
  #     pause_duration: 0.4,
  #     pitch_variation: 6,
  #     rate: 'medium'
  #   )
  class ProsodicPattern
    # @return [String] pattern name
    # @return [Float] segment duration in seconds
    # @return [Float] pause duration in seconds
    # @return [Integer] pitch variation percentage
    # @return [String] speaking rate (slow, medium, fast)
    attr_reader :name, :segment_duration, :pause_duration, :pitch_variation, :rate

    # Initialize a new prosodic pattern
    #
    # @param name [String] descriptive name for the pattern
    # @param segment_duration [Float] duration of speech segments in seconds
    # @param pause_duration [Float] duration of pauses between segments in seconds
    # @param pitch_variation [Integer] pitch variation percentage (1-15)
    # @param rate [String] speaking rate ('slow', 'medium', 'fast')
    def initialize(name:, segment_duration: 1.0, pause_duration: 0.35, 
                  pitch_variation: 5, rate: 'medium')
      @name = name
      @segment_duration = segment_duration
      @pause_duration = pause_duration
      @pitch_variation = pitch_variation
      @rate = rate
    end

    # Convert pattern to hash representation
    #
    # @return [Hash] pattern attributes as hash
    def to_h
      {
        segment_duration: @segment_duration,
        pause_duration: @pause_duration,
        pitch_variation: @pitch_variation,
        rate: @rate
      }
    end
  end
end