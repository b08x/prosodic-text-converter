# frozen_string_literal: true

require 'open3'
require 'fileutils'

module ProsodicTextConverter
  # Spectrogram generation using SoX for audio visualization and analysis
  #
  # @example Basic usage
  #   generator = SpectrogramGenerator.new
  #   result = generator.generate('voice.wav', output_dir: './spectrograms')
  #   puts result[:spectrogram_file]
  class SpectrogramGenerator
    # @return [Hash] generation options
    attr_reader :options

    # Initialize spectrogram generator with customizable options
    #
    # @param options [Hash] spectrogram generation options
    # @option options [Integer] :z_axis_range dynamic range in dB (default: 100)
    # @option options [Integer] :x_axis_pixels_per_sec time resolution (default: 200)
    # @option options [Integer] :y_axis_bins frequency bins (default: 513)
    # @option options [String] :window_function windowing function (default: 'Hann')
    # @raise [RuntimeError] if SoX is not available
    def initialize(options: {})
      @options = default_options.merge(options)
      validate_dependencies
    end

    # Generate spectrogram from audio file using SoX
    #
    # @param audio_file [String] path to input audio file
    # @param output_dir [String] directory for output spectrogram
    # @return [Hash] generation results with file paths and metadata
    # @raise [RuntimeError] if audio file not found or generation fails
    def generate(audio_file, output_dir: './spectrograms')
      FileUtils.mkdir_p(output_dir)
      
      unless File.exist?(audio_file)
        raise "Audio file not found: #{audio_file}"
      end

      output_file = File.join(output_dir, "#{File.basename(audio_file, '.*')}_spectrogram.png")
      
      command = build_sox_command(audio_file, output_file)
      stdout, stderr, status = Open3.capture3(*command)
      
      unless status.success?
        raise "Spectrogram generation failed: #{stderr}"
      end
      
      unless File.exist?(output_file)
        raise "Expected spectrogram file not found: #{output_file}"
      end
      
      {
        input_file: audio_file,
        spectrogram_file: output_file,
        generation_output: stdout,
        file_size: File.size(output_file)
      }
    end

    private

    # Validate that SoX is available on the system
    #
    # @raise [RuntimeError] if SoX is not found
    def validate_dependencies
      stdout, stderr, status = Open3.capture3('which', 'sox')
      unless status.success?
        raise "SoX not found. Please install SoX: apt-get install sox (Linux) or brew install sox (macOS)"
      end
    end

    # Build SoX command for spectrogram generation
    #
    # @param audio_file [String] input audio file path
    # @param output_file [String] output spectrogram file path
    # @return [Array<String>] command arguments for SoX
    def build_sox_command(audio_file, output_file)
      title = "Prosody Spectrogram: #{File.basename(audio_file)}"
      
      [
        'sox',
        audio_file,
        '-n',
        'spectrogram',
        '-o', output_file,
        '-t', title,
        '-l',  # Include axis labels
        '-m',  # Monochrome (grayscale)
        '-z', @options[:z_axis_range].to_s,
        '-y', @options[:y_axis_bins].to_s,
        '-X', @options[:x_axis_pixels_per_sec].to_s,
        '-w', @options[:window_function]
      ]
    end

    # Default options for spectrogram generation
    #
    # @return [Hash] default configuration options
    def default_options
      {
        z_axis_range: 100,           # Dynamic range in dB (100-120 good for speech)
        x_axis_pixels_per_sec: 200,  # Time resolution (pixels per second)
        y_axis_bins: 513,            # Frequency bins (1024-point FFT)
        window_function: 'Hann'      # Windowing function
      }
    end
  end
end