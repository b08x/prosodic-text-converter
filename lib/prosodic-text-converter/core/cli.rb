# frozen_string_literal: true

require_relative 'converter'

module ProsodicTextConverter
  # CLI interface
  class CLI
    def self.run(args = ARGV)
      if args.empty? || args.include?('--help')
        print_usage
        return
      end

      if args.include?('--list-backends')
        list_available_backends
        return
      end

      pattern_name = args.find { |arg| arg.start_with?('--pattern=') }&.split('=', 2)&.last&.to_sym
      provider_arg = args.find { |arg| arg.start_with?('--provider=') }&.split('=', 2)&.last&.to_sym
      model_arg = args.find { |arg| arg.start_with?('--model=') }&.split('=', 2)&.last
      pitch_backend_arg = args.find { |arg| arg.start_with?('--pitch-backend=') }&.split('=', 2)&.last&.to_sym
      audio_file = args.find { |arg| arg.start_with?('--audio=') }&.split('=', 2)&.last
      spectrogram_dir = args.find { |arg| arg.start_with?('--spectrogram-dir=') }&.split('=', 2)&.last || './spectrograms'
      
      # Get non-option arguments
      input_files = args.reject { |arg| arg.start_with?('--') }
      input_file = input_files.first
      
      pattern = Converter.predefined_patterns[pattern_name] if pattern_name
      provider = provider_arg || :openai
      model = model_arg || 'gpt-4'
      pitch_backend = pitch_backend_arg || :aubio
      
      # Validate pitch backend
      available_backends = Converter.available_pitch_backends
      if available_backends.empty?
        $stderr.puts "Error: No pitch analysis backends available."
        $stderr.puts "Install aubio: apt-get install aubio-tools (Linux) or brew install aubio (macOS)"
        exit 1
      elsif !available_backends.include?(pitch_backend)
        $stderr.puts "Error: Pitch backend '#{pitch_backend}' not available."
        $stderr.puts "Available backends: #{available_backends.join(', ')}"
        exit 1
      end
      
      converter = Converter.new(
        pattern: pattern,
        provider: provider,
        model: model,
        pitch_backend: pitch_backend
      )
      
      # Handle audio analysis mode
      if audio_file
        if args.include?('--analyze-only')
          result = converter.extract_pattern_from_audio(audio_file, output_dir: spectrogram_dir)
          puts "Audio analysis complete:"
          puts "Spectrogram: #{result[:spectrogram_file]}"
          puts "Pitch backend: #{result[:pitch_backend_used]}"
          puts "Extracted pattern: #{result[:extracted_pattern]}"
          
          if result[:analysis][:prosodic_features][:analysis_method]
            puts "Analysis method: #{result[:analysis][:prosodic_features][:analysis_method]}"
          end
          
          return
        end
        
        unless input_file
          $stderr.puts "Error: Text file required when using --audio option"
          exit 1
        end
      end
      
      # Get text input
      text = if input_file && File.exist?(input_file)
              File.read(input_file)
            elsif !audio_file
              $stdin.read
            else
              File.read(input_file)
            end

      # Process based on mode
      result = if audio_file
                converter.convert_with_audio_analysis(text.strip, audio_file)
              else
                converter.convert(text.strip)
              end
      
      puts result[:ssml_output]
      
      if args.include?('--verbose')
        $stderr.puts "\n--- Analysis ---"
        $stderr.puts "Pattern: #{result[:pattern_used]}"
        $stderr.puts "Chunks: #{result[:chunks_processed]}"
        $stderr.puts "Timing: #{result[:timing_analysis]}"
        
        if result[:audio_analysis]
          $stderr.puts "\n--- Audio Analysis ---"
          $stderr.puts "Spectrogram: #{result[:audio_analysis][:spectrogram_file]}"
          $stderr.puts "Pitch backend: #{result[:audio_analysis][:pitch_backend_used]}"
          $stderr.puts "Prosodic features: #{result[:audio_analysis][:analysis][:prosodic_features]}"
          
          if result[:audio_analysis][:analysis][:pitch_analysis]
            pitch_data = result[:audio_analysis][:analysis][:pitch_analysis]
            $stderr.puts "Pitch data points: #{pitch_data&.length || 0}"
          end
        end
      end
    rescue => e
      $stderr.puts "Error: #{e.message}"
      exit 1
    end

    def self.list_available_backends
      backends = Converter.available_pitch_backends
      
      puts "Available pitch analysis backends:"
      if backends.empty?
        puts "  None found. Install aubio or sonic-annotator."
      else
        backends.each do |backend|
          status = case backend
                  when :aubio
                    "✓ Aubio - Fast, accurate, excellent for speech (recommended for most use cases)"
                  when :sonic_annotator  
                    "✓ Sonic Annotator - Research-grade analysis with comprehensive prosodic metrics"
                  else
                    "✓ #{backend}"
                  end
          puts "  #{status}"
        end
      end
      
      puts "\nBackend Features:"
      puts "  Aubio:"
      puts "    • YIN pitch tracking algorithm"
      puts "    • Fast processing, low memory usage"
      puts "    • Excellent for production pipelines"
      puts "    • Speech-optimized frequency analysis"
      puts ""
      puts "  Sonic Annotator:"
      puts "    • pYIN probabilistic pitch tracking"
      puts "    • Advanced tempo and rhythm analysis"
      puts "    • Multiple simultaneous feature extraction"
      puts "    • Research-grade accuracy with confidence measures"
      puts "    • Extensible plugin ecosystem"
      puts ""
      puts "Installation:"
      puts "  Aubio: apt-get install aubio-tools (Linux) or brew install aubio (macOS)"
      puts "  Sonic Annotator: https://vamp-plugins.org/sonic-annotator/"
      puts "    • Also install Vamp plugins: pyin, vamp-example-plugins"
      puts "    • macOS: brew install sonic-visualiser (includes sonic-annotator)"
    end

    def self.print_usage
      puts <<~USAGE
        Prosodic Text Converter
        
        Usage: #{$0} [options] [input_file]
        
        Options:
          --pattern=NAME          Use predefined pattern (deliberate, rapid, contemplative)
          --audio=FILE           Extract prosodic pattern from audio file
          --pitch-backend=NAME   Pitch analysis backend (aubio, sonic_annotator)
          --analyze-only         Only analyze audio file, don't convert text
          --spectrogram-dir=DIR  Output directory for spectrograms (default: ./spectrograms)
          --provider=NAME        LLM provider (openai, anthropic, ollama, etc.)
          --model=NAME           Model name (gpt-4, claude-3-sonnet, etc.)
          --verbose              Show analysis information
          --list-backends        Show available pitch analysis backends
          --help                Show this help
          
        Patterns:
          deliberate             1.0s segments, 350ms pauses (default)
          rapid                  0.6s segments, 200ms pauses  
          contemplative          1.4s segments, 500ms pauses
          
        Providers (via RubyLLM):
          openai                OpenAI GPT models (requires OPENAI_API_KEY)
          anthropic             Anthropic Claude models (requires ANTHROPIC_API_KEY)
          ollama                Local Ollama models
          
        Pitch Backends:
          aubio                 Fast, accurate, recommended for production use
          sonic_annotator       Research-grade with comprehensive prosodic analysis
          
        Audio Analysis:
          Requires SoX and a pitch analysis backend (aubio or sonic-annotator)
          Supported formats: WAV, MP3, FLAC, etc. (anything SoX can read)
          
        Backend Selection Guide:
          • Use aubio for: Production pipelines, fast processing, speech applications
          • Use sonic_annotator for: Research, detailed prosodic analysis, academic work
          
        Examples:
          # List available pitch backends and their features
          #{$0} --list-backends
          
          # Basic text conversion
          echo "Hello world" | #{$0}
          
          # Use predefined pattern
          #{$0} --pattern=rapid --provider=anthropic input.txt
          
          # Fast analysis with aubio (recommended for most use cases)
          #{$0} --audio=voice_sample.wav --pitch-backend=aubio input.txt
          
          # Comprehensive research-grade analysis with sonic-annotator
          #{$0} --audio=speaker.wav --pitch-backend=sonic_annotator input.txt
          
          # Analyze audio only with detailed metrics
          #{$0} --audio=voice_sample.wav --pitch-backend=sonic_annotator --analyze-only --verbose
          
          # Compare backends on same audio
          #{$0} --audio=test.wav --pitch-backend=aubio --analyze-only > aubio_analysis.txt
          #{$0} --audio=test.wav --pitch-backend=sonic_annotator --analyze-only > sonic_analysis.txt
          
          # Full pipeline with research-grade analysis
          #{$0} --audio=speaker.wav --pitch-backend=sonic_annotator --provider=anthropic --model=claude-3-sonnet text.txt
      USAGE
    end
  end
end