# frozen_string_literal: true

require 'open3'
require 'fileutils'

module ProsodicTextConverter
  # Spectrogram generation using SoX
  class SpectrogramGenerator
    attr_reader :options

    def initialize(options: {})
      @options = default_options.merge(options)
      validate_dependencies
    end

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

    def validate_dependencies
      stdout, stderr, status = Open3.capture3('which', 'sox')
      unless status.success?
        raise "SoX not found. Please install SoX: apt-get install sox (Linux) or brew install sox (macOS)"
      end
    end

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