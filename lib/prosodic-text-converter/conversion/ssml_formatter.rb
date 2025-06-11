# frozen_string_literal: true

require 'nokogiri'

module ProsodicTextConverter
  # SSML formatter and validator
  class SSMLFormatter
    def initialize
      @builder = Nokogiri::XML::Builder.new(encoding: 'UTF-8')
    end

    def validate_ssml(ssml_text)
      begin
        doc = Nokogiri::XML(ssml_text) { |config| config.strict }
        doc.errors.empty?
      rescue => e
        false
      end
    end

    def clean_ssml(ssml_text)
      # Remove any malformed tags, normalize whitespace
      doc = Nokogiri::XML(ssml_text)
      doc.to_xml(indent: 2, encoding: 'UTF-8')
    rescue => e
      ssml_text # Return original if parsing fails
    end

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