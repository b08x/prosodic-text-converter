# frozen_string_literal: true

module ProsodicTextConverter
  # Prosodic pattern definition and text conversion
  class ProsodicPattern
    attr_reader :name, :segment_duration, :pause_duration, :pitch_variation, :rate

    def initialize(name:, segment_duration: 1.0, pause_duration: 0.35, 
                  pitch_variation: 5, rate: 'medium')
      @name = name
      @segment_duration = segment_duration
      @pause_duration = pause_duration
      @pitch_variation = pitch_variation
      @rate = rate
    end

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