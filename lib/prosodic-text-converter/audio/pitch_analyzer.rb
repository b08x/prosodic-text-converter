# frozen_string_literal: true

require 'open3'
require 'fileutils'
require 'csv'

module ProsodicTextConverter
  # Abstract interface for pitch analysis backends
  class PitchAnalyzer
    def analyze(audio_file)
      raise NotImplementedError, "Subclasses must implement analyze method"
    end

    def calculate_pitch_variation(pitch_data)
      return 5.0 if pitch_data.empty?
      
      frequencies = pitch_data.map { |p| p[:frequency] }.reject(&:zero?)
      return 5.0 if frequencies.length < 2
      
      mean_freq = frequencies.sum / frequencies.length.to_f
      variance = frequencies.map { |f| (f - mean_freq) ** 2 }.sum / frequencies.length.to_f
      std_dev = Math.sqrt(variance)
      
      # Convert to percentage variation
      coefficient_of_variation = (std_dev / mean_freq) * 100
      coefficient_of_variation.clamp(1.0, 15.0)
    end
  end

  # Aubio-based pitch analysis implementation
  class AubioPitchAnalyzer < PitchAnalyzer
    def initialize(algorithm: 'yin', hop_size: 512, buffer_size: 1024)
      @algorithm = algorithm
      @hop_size = hop_size
      @buffer_size = buffer_size
      validate_dependencies
    end

    def analyze(audio_file)
      unless File.exist?(audio_file)
        raise "Audio file not found: #{audio_file}"
      end

      # Run aubio pitch analysis
      stdout, stderr, status = Open3.capture3(
        'aubio', 'pitch', audio_file,
        '-m', @algorithm,
        '-u', 'Hz',
        '-H', @hop_size.to_s,
        '-B', @buffer_size.to_s
      )

      unless status.success?
        raise "Aubio pitch analysis failed: #{stderr}"
      end

      parse_aubio_output(stdout)
    end

    private

    def validate_dependencies
      stdout, stderr, status = Open3.capture3('which', 'aubio')
      unless status.success?
        raise "Aubio not found. Install with: apt-get install aubio-tools (Linux) or brew install aubio (macOS)"
      end
    end

    def parse_aubio_output(output)
      pitch_data = []
      
      output.lines.each do |line|
        parts = line.strip.split(/\s+/)
        next if parts.length < 2
        
        timestamp = parts[0].to_f
        frequency = parts[1].to_f
        
        # Filter out unvoiced segments (aubio outputs 0.0 for silence)
        next if frequency < 50.0 || frequency > 800.0  # Reasonable speech range
        
        pitch_data << {
          timestamp: timestamp,
          frequency: frequency
        }
      end
      
      pitch_data
    end
  end

  # Sonic Annotator implementation with comprehensive prosodic analysis
  class SonicAnnotatorPitchAnalyzer < PitchAnalyzer
    def initialize(plugin: 'pyin:pyin:f0candidates', step_size: 256, block_size: 2048)
      @plugin = plugin
      @step_size = step_size
      @block_size = block_size
      @transform_dir = File.join(File.dirname(__FILE__), '..', '..', '..', 'transforms')
      
      ensure_transform_directory
      ensure_all_transforms
      validate_dependencies
    end

    def analyze(audio_file)
      unless File.exist?(audio_file)
        raise "Audio file not found: #{audio_file}"
      end

      # Create comprehensive analysis with multiple transforms
      pitch_data = extract_pitch_data(audio_file)
      tempo_data = extract_tempo_data(audio_file)
      
      # Combine results for comprehensive prosodic analysis
      combine_analysis_results(pitch_data, tempo_data)
    end

    def extract_pitch_data(audio_file)
      transform_file = create_pyin_transform
      
      stdout, stderr, status = Open3.capture3(
        'sonic-annotator', '-q', 
        '-t', transform_file,
        audio_file,
        '-w', 'csv', '--csv-stdout'
      )

      unless status.success?
        raise "Sonic Annotator pitch analysis failed: #{stderr}"
      end

      parse_pyin_output(stdout)
    end

    def extract_tempo_data(audio_file)
      # Optional: Extract tempo/rhythm information for prosodic analysis
      transform_file = create_tempo_transform
      
      stdout, stderr, status = Open3.capture3(
        'sonic-annotator', '-q',
        '-t', transform_file, 
        audio_file,
        '-w', 'csv', '--csv-stdout'
      )

      # Don't fail if tempo analysis fails - it's supplementary
      return [] unless status.success?
      
      parse_tempo_output(stdout)
    end

    private

    def validate_dependencies
      stdout, stderr, status = Open3.capture3('which', 'sonic-annotator')
      unless status.success?
        raise "Sonic Annotator not found. Install from: https://vamp-plugins.org/sonic-annotator/"
      end

      # Check for required Vamp plugins
      check_vamp_plugins
    end

    def check_vamp_plugins
      stdout, stderr, status = Open3.capture3('sonic-annotator', '-l')
      
      required_plugins = ['pyin:pyin', 'vamp-example-plugins:fixedtempo']
      missing_plugins = []
      
      required_plugins.each do |plugin|
        unless stdout.include?(plugin)
          missing_plugins << plugin
        end
      end
      
      unless missing_plugins.empty?
        puts "Warning: Missing Vamp plugins: #{missing_plugins.join(', ')}"
        puts "Install with your package manager or from: https://vamp-plugins.org/"
      end
    end

    def ensure_transform_directory
      FileUtils.mkdir_p(@transform_dir)
    end

    def ensure_all_transforms
      # Create all transform files programmatically to eliminate dependency on setup scripts
      create_pyin_transform
      create_tempo_transform
      create_fundamental_freq_transform
      create_onset_detection_transform
    end

    def create_pyin_transform
      transform_file = File.join(@transform_dir, 'pyin_pitch.n3')
      
      transform_content = <<~N3
        @prefix xsd:      <http://www.w3.org/2001/XMLSchema#> .
        @prefix vamp:     <http://purl.org/ontology/vamp/> .
        @prefix :         <#> .

        :transform_plugin a vamp:Plugin ;
            vamp:identifier "pyin" .

        :transform_library a vamp:PluginLibrary ;
            vamp:identifier "pyin" ;
            vamp:available_plugin :transform_plugin .

        :transform a vamp:Transform ;
            vamp:plugin :transform_plugin ;
            vamp:step_size "#{@step_size}"^^xsd:int ; 
            vamp:block_size "#{@block_size}"^^xsd:int ; 
            vamp:plugin_version """3""" ; 
            vamp:parameter_binding [
                vamp:parameter [ vamp:identifier "lowampsuppression" ] ;
                vamp:value "0.1"^^xsd:float ;
            ] ;
            vamp:parameter_binding [
                vamp:parameter [ vamp:identifier "onsetsensitivity" ] ;
                vamp:value "0.7"^^xsd:float ;
            ] ;
            vamp:parameter_binding [
                vamp:parameter [ vamp:identifier "outputunvoiced" ] ;
                vamp:value "0"^^xsd:float ;
            ] ;
            vamp:parameter_binding [
                vamp:parameter [ vamp:identifier "precisetime" ] ;
                vamp:value "1"^^xsd:float ;
            ] ;
            vamp:output [ vamp:identifier "smoothedpitchtrack" ] .
      N3

      File.write(transform_file, transform_content)
      transform_file
    end

    def create_tempo_transform
      transform_file = File.join(@transform_dir, 'tempo.n3')
      
      transform_content = <<~N3
        @prefix xsd:      <http://www.w3.org/2001/XMLSchema#> .
        @prefix vamp:     <http://purl.org/ontology/vamp/> .
        @prefix :         <#> .

        :transform_plugin a vamp:Plugin ;
            vamp:identifier "fixedtempo" .

        :transform_library a vamp:PluginLibrary ;
            vamp:identifier "vamp-example-plugins" ;
            vamp:available_plugin :transform_plugin .

        :transform a vamp:Transform ;
            vamp:plugin :transform_plugin ;
            vamp:step_size "256"^^xsd:int ;
            vamp:block_size "256"^^xsd:int ;
            vamp:plugin_version """1""" ;
            vamp:parameter_binding [
                vamp:parameter [ vamp:identifier "maxbpm" ] ;
                vamp:value "220"^^xsd:float ;
            ] ;
            vamp:parameter_binding [
                vamp:parameter [ vamp:identifier "minbpm" ] ;
                vamp:value "20"^^xsd:float ;
            ] ;
            vamp:output [ vamp:identifier "tempo" ] .
      N3

      File.write(transform_file, transform_content)
      transform_file
    end

    def create_fundamental_freq_transform
      transform_file = File.join(@transform_dir, 'fundamental_freq.n3')
      
      transform_content = <<~N3
        @prefix xsd:      <http://www.w3.org/2001/XMLSchema#> .
        @prefix vamp:     <http://purl.org/ontology/vamp/> .
        @prefix :         <#> .

        :transform_plugin a vamp:Plugin ;
            vamp:identifier "f0" .

        :transform_library a vamp:PluginLibrary ;
            vamp:identifier "vamp-libxtract" ;
            vamp:available_plugin :transform_plugin .

        :transform a vamp:Transform ;
            vamp:plugin :transform_plugin ;
            vamp:step_size "512"^^xsd:int ;
            vamp:block_size "1024"^^xsd:int ;
            vamp:plugin_version """4""" ;
            vamp:output [ vamp:identifier "f0" ] .
      N3

      File.write(transform_file, transform_content)
      transform_file
    end

    def create_onset_detection_transform
      transform_file = File.join(@transform_dir, 'onset_detection.n3')
      
      transform_content = <<~N3
        @prefix xsd:      <http://www.w3.org/2001/XMLSchema#> .
        @prefix vamp:     <http://purl.org/ontology/vamp/> .
        @prefix :         <#> .

        :transform_plugin a vamp:Plugin ;
            vamp:identifier "aubionotes" .

        :transform_library a vamp:PluginLibrary ;
            vamp:identifier "vamp-aubio" ;
            vamp:available_plugin :transform_plugin .

        :transform a vamp:Transform ;
            vamp:plugin :transform_plugin ;
            vamp:step_size "512"^^xsd:int ; 
            vamp:block_size "2048"^^xsd:int ; 
            vamp:plugin_version """4""" ; 
            vamp:parameter_binding [
                vamp:parameter [ vamp:identifier "onsettype" ] ;
                vamp:value "3"^^xsd:float ;
            ] ;
            vamp:parameter_binding [
                vamp:parameter [ vamp:identifier "peakpickthreshold" ] ;
                vamp:value "0.3"^^xsd:float ;
            ] ;
            vamp:parameter_binding [
                vamp:parameter [ vamp:identifier "silencethreshold" ] ;
                vamp:value "-70"^^xsd:float ;
            ] ;
            vamp:output [ vamp:identifier "notes" ] .
      N3

      File.write(transform_file, transform_content)
      transform_file
    end

    def parse_pyin_output(output)
      pitch_data = []
      
      CSV.parse(output.strip, col_sep: ',') do |row|
        next if row.length < 3
        
        timestamp = row[0].to_f
        frequency = row[2].to_f  # pYIN smoothed pitch track
        
        # Filter reasonable speech range and non-zero values
        next if frequency <= 0 || frequency < 50.0 || frequency > 800.0
        
        pitch_data << {
          timestamp: timestamp,
          frequency: frequency,
          confidence: 1.0  # pYIN provides high-confidence smoothed output
        }
      end
      
      pitch_data
    end

    def parse_tempo_output(output)
      tempo_data = []
      
      CSV.parse(output.strip, col_sep: ',') do |row|
        next if row.length < 3
        
        timestamp = row[0].to_f
        tempo = row[2].to_f
        
        next if tempo <= 0
        
        tempo_data << {
          timestamp: timestamp,
          tempo: tempo
        }
      end
      
      tempo_data
    end

    def combine_analysis_results(pitch_data, tempo_data)
      # Return pitch data with additional tempo context
      result = pitch_data.dup
      
      # Add tempo information to the analysis
      unless tempo_data.empty?
        avg_tempo = tempo_data.map { |t| t[:tempo] }.sum / tempo_data.length.to_f
        
        # Enhance each pitch point with rhythmic context
        result.each do |point|
          # Find closest tempo measurement
          closest_tempo = tempo_data.min_by { |t| (t[:timestamp] - point[:timestamp]).abs }
          point[:tempo_context] = closest_tempo ? closest_tempo[:tempo] : avg_tempo
        end
      end
      
      result
    end
  end

  # Factory for creating pitch analyzers
  class PitchAnalyzerFactory
    def self.create(backend: :aubio, **options)
      case backend
      when :aubio
        AubioPitchAnalyzer.new(**options)
      when :sonic_annotator
        SonicAnnotatorPitchAnalyzer.new(**options)
      else
        raise ArgumentError, "Unknown pitch analyzer backend: #{backend}"
      end
    end

    def self.available_backends
      backends = []
      
      # Check for aubio
      if system('which aubio > /dev/null 2>&1')
        backends << :aubio
      end
      
      # Check for sonic-annotator
      if system('which sonic-annotator > /dev/null 2>&1')
        backends << :sonic_annotator
      end
      
      backends
    end
  end
end