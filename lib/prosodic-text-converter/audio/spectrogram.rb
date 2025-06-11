# frozen_string_literal: true

require 'open3'
require 'fileutils'

module ProsodicTextConverter
  # Spectrogram generation using FFmpeg
  class SpectrogramGenerator
    def initialize(script_path: nil)
      validate_dependencies
    end

    def generate(audio_file, output_dir: './spectrograms')
      FileUtils.mkdir_p(output_dir)
      
      unless File.exist?(audio_file)
        raise "Audio file not found: #{audio_file}"
      end

      output_file = File.join(output_dir, "#{File.basename(audio_file, '.*')}_spectrogram.png")
      
      # Build and run the FFmpeg command
      command = build_ffmpeg_command(audio_file, output_file)
      stdout, stderr, status = Open3.capture3(command)
      
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
      stdout, stderr, status = Open3.capture3('which', 'ffmpeg')
      unless status.success?
        raise "FFmpeg not found. Please install FFmpeg: apt-get install ffmpeg (Linux) or brew install ffmpeg (macOS)"
      end
    end

    def build_ffmpeg_command(audio_file, output_file)
      options = default_options
      
      command = ['ffmpeg', '-y', '-i', audio_file]

      # Audio Normalization
      if options[:normalise]
        command << '-af' << 'loudnorm=I=-16:TP=-1.5:LRA=11'
      end

      # Noise Reduction (if enabled)
      if options[:noise_reduction]
        command << '-af' << 'afftdn=nr=true'
      end

      command += [
        '-lavfi',
        "spectrogram=s=1024x512:window_length=#{options[:window_size]}:overlap=#{options[:overlap]}:frequency_range=#{options[:frequency_range]}",
        '-frames:v', '1',
        output_file
      ]

      command.join(' ')
    end

    def default_options
      {
        window_size: 0.05, # seconds
        overlap: 0.75,     # 75% overlap
        frequency_range: '0-8000', # Hz
        normalise: true,   # Normalise Audio
        noise_reduction: true # Apply Noise Reduction
      }
    end
  end
end