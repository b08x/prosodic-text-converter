# frozen_string_literal: true

require 'nokogiri'
require_relative '../core/logging'

module ProsodicTextConverter
  # SSML formatter and validator for speech synthesis markup
  #
  # @example Basic usage
  #   formatter = SSMLFormatter.new
  #   clean_ssml = formatter.clean_ssml(raw_ssml)
  #   timing = formatter.extract_timing_info(clean_ssml)
  class SSMLFormatter
    include Logging
    # Initialize SSML formatter with XML builder
    def initialize
      @builder = Nokogiri::XML::Builder.new(encoding: 'UTF-8')
    end

    # Validate SSML markup for syntax correctness
    #
    # @param ssml_text [String] SSML markup to validate
    # @return [Boolean] true if valid, false otherwise
    def validate_ssml(ssml_text)
      doc = Nokogiri::XML(ssml_text) { |config| config.strict }
      doc.errors.empty?
    rescue StandardError
      false
    end

    # Clean and normalize SSML markup
    #
    # @param ssml_text [String] raw SSML markup
    # @return [String] cleaned and formatted SSML
    def clean_ssml(ssml_text)
      # Remove any malformed tags, normalize whitespace
      doc = Nokogiri::XML(ssml_text)
      doc.to_xml(indent: 2, encoding: 'UTF-8')
    rescue StandardError
      ssml_text # Return original if parsing fails
    end

    # Extract timing information from SSML markup
    #
    # @param ssml_text [String] SSML markup
    # @return [Hash] timing analysis with segments, breaks, and durations
    def extract_timing_info(ssml_text)
      doc = Nokogiri::XML(ssml_text)

      segments = doc.xpath('//prosody').length
      breaks = doc.xpath('//break').map { |b| b['time'] }.compact
      total_break_time = breaks.sum { |t| t.gsub(/\D/, '').to_f / 1000 }

      {
        segments: segments,
        total_breaks: breaks.length,
        estimated_break_duration: total_break_time,
        break_times: breaks
      }
    end
  end
end
