# frozen_string_literal: true

require 'open3'
require 'fileutils'
require 'csv'
require 'logger'
require 'timeout'

module ProsodicTextConverter
  # Abstract interface for pitch analysis backends
  #
  # @abstract Subclasses must implement {#analyze} method
  class PitchAnalyzer
    # @return [Logger] logger instance
    attr_reader :logger

    # Initialize the pitch analyzer
    #
    # @param logger [Logger, nil] custom logger instance
    def initialize(logger: nil)
      @logger = logger || setup_logger
    end

    # Analyze audio file for pitch information
    #
    # @param audio_file [String] path to audio file
    # @return [Array<Hash>] pitch analysis data
    # @raise [NotImplementedError] must be implemented by subclasses
    def analyze(audio_file)
      raise NotImplementedError, "Subclasses must implement analyze method"
    end

    protected

    # Setup default logger
    #
    # @return [Logger] configured logger
    def setup_logger
      Logger.new($stderr).tap do |log|
        log.level = Logger::INFO
        log.formatter = proc do |severity, datetime, progname, msg|
          "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] PitchAnalyzer #{severity}: #{msg}\n"
        end
      end
    end

    # Validate audio file before analysis
    #
    # @param audio_file [String] path to audio file
    # @raise [ArgumentError] if file is invalid
    def validate_audio_file(audio_file)
      if audio_file.nil? || audio_file.strip.empty?
        error_msg = "Audio file path cannot be nil or empty"
        @logger.error(error_msg)
        raise ArgumentError, error_msg
      end
      
      unless File.exist?(audio_file)
        error_msg = "Audio file not found: #{audio_file}"
        @logger.error(error_msg)
        raise ArgumentError, error_msg
      end
      
      unless File.readable?(audio_file)
        error_msg = "Audio file not readable: #{audio_file}"
        @logger.error(error_msg)
        raise ArgumentError, error_msg
      end
    end

    public

    # Calculate pitch variation coefficient from pitch data
    #
    # @param pitch_data [Array<Hash>] pitch analysis data
    # @return [Float] pitch variation percentage (1.0-15.0)
    def calculate_pitch_variation(pitch_data)
      begin
        return 5.0 if pitch_data.empty?
        
        frequencies = pitch_data.map { |p| p[:frequency] }.reject(&:zero?)
        return 5.0 if frequencies.length < 2
        
        mean_freq = frequencies.sum / frequencies.length.to_f
        variance = frequencies.map { |f| (f - mean_freq) ** 2 }.sum / frequencies.length.to_f
        std_dev = Math.sqrt(variance)
        
        # Convert to percentage variation
        coefficient_of_variation = (std_dev / mean_freq) * 100
        result = coefficient_of_variation.clamp(1.0, 15.0)
        
        @logger.debug("Calculated pitch variation: #{result.round(2)}% (#{frequencies.length} data points)")
        result
        
      rescue StandardError => e
        @logger.warn("Error calculating pitch variation: #{e.message}, using default")
        5.0
      end
    end
  end

  # Aubio-based pitch analysis implementation using YIN algorithm
  #
  # @example Basic usage
  #   analyzer = AubioPitchAnalyzer.new
  #   pitch_data = analyzer.analyze('voice.wav')
  class AubioPitchAnalyzer < PitchAnalyzer
    # @return [String] pitch detection algorithm
    attr_reader :algorithm
    
    # @return [Integer] hop size for analysis
    attr_reader :hop_size
    
    # @return [Integer] buffer size for analysis
    attr_reader :buffer_size

    # Initialize Aubio pitch analyzer
    #
    # @param algorithm [String] pitch detection algorithm ('yin', 'mcomb', 'fcomb', 'schmitt')
    # @param hop_size [Integer] hop size in samples
    # @param buffer_size [Integer] buffer size in samples
    # @param logger [Logger, nil] custom logger instance
    # @raise [RuntimeError] if aubio is not available
    def initialize(algorithm: 'yin', hop_size: 512, buffer_size: 1024, logger: nil)
      super(logger: logger)
      @algorithm = algorithm
      @hop_size = hop_size
      @buffer_size = buffer_size
      
      begin
        validate_dependencies
        @logger.info("Aubio analyzer initialized (#{@algorithm}, hop: #{@hop_size}, buffer: #{@buffer_size})")
      rescue StandardError => e
        @logger.error("Failed to initialize Aubio analyzer: #{e.message}")
        raise
      end
    end

    # Analyze audio file using Aubio
    #
    # @param audio_file [String] path to audio file
    # @return [Array<Hash>] pitch analysis data with timestamps and frequencies
    # @raise [ArgumentError] if audio file is invalid
    # @raise [RuntimeError] if analysis fails
    def analyze(audio_file)
      validate_audio_file(audio_file)
      
      begin
        @logger.info("Starting Aubio pitch analysis: #{File.basename(audio_file)}")
        start_time = Time.now
        
        # Run aubio pitch analysis with timeout
        stdout, stderr, status = Timeout.timeout(300) do  # 5 minute timeout
          Open3.capture3(
            'aubio', 'pitch', audio_file,
            '-m', @algorithm,
            '-u', 'Hz',
            '-H', @hop_size.to_s,
            '-B', @buffer_size.to_s
          )
        end

        unless status.success?
          error_msg = "Aubio pitch analysis failed: #{stderr.strip}"
          @logger.error(error_msg)
          raise RuntimeError, error_msg
        end

        pitch_data = parse_aubio_output(stdout)
        analysis_time = Time.now - start_time
        
        @logger.info("Aubio analysis completed in #{analysis_time.round(2)}s, #{pitch_data.length} data points")
        pitch_data
        
      rescue Timeout::Error => e
        error_msg = "Aubio analysis timed out after 5 minutes"
        @logger.error(error_msg)
        raise RuntimeError, error_msg
      rescue StandardError => e
        error_msg = "Aubio analysis failed: #{e.message}"
        @logger.error(error_msg)
        @logger.debug("Backtrace: #{e.backtrace.join("\n")}")
        raise RuntimeError, error_msg
      end
    end

    private

    # Validate that Aubio is available
    #
    # @raise [RuntimeError] if aubio is not found
    def validate_dependencies
      begin
        stdout, stderr, status = Timeout.timeout(10) do
          Open3.capture3('which', 'aubiopitch')
        end
        
        unless status.success?
          error_msg = "Aubio not found. Install with: apt-get install aubio-tools (Linux) or brew install aubio (macOS)"
          @logger.error(error_msg)
          raise RuntimeError, error_msg
        end
        
        @logger.debug("Aubio found and available")
        
      rescue Timeout::Error
        error_msg = "Timeout checking for Aubio installation"
        @logger.error(error_msg)
        raise RuntimeError, error_msg
      rescue StandardError => e
        error_msg = "Error checking Aubio installation: #{e.message}"
        @logger.error(error_msg)
        raise RuntimeError, error_msg
      end
    end

    # Parse Aubio output into structured pitch data
    #
    # @param output [String] raw aubio output
    # @return [Array<Hash>] parsed pitch data
    def parse_aubio_output(output)
      pitch_data = []
      processed_lines = 0
      filtered_lines = 0
      
      begin
        output.lines.each do |line|
          processed_lines += 1
          parts = line.strip.split(/\s+/)
          next if parts.length < 2
          
          timestamp = parts[0].to_f
          frequency = parts[1].to_f
          
          # Filter out unvoiced segments and unreasonable frequencies
          if frequency < 50.0 || frequency > 800.0  # Reasonable speech range
            filtered_lines += 1
            next
          end
          
          pitch_data << {
            timestamp: timestamp,
            frequency: frequency
          }
        end
        
        @logger.debug("Parsed #{processed_lines} lines, filtered #{filtered_lines}, kept #{pitch_data.length}")
        
        if pitch_data.empty?
          @logger.warn("No valid pitch data extracted from audio")
        else
          freq_range = pitch_data.map { |p| p[:frequency] }
          @logger.debug("Frequency range: #{freq_range.min.round(1)}-#{freq_range.max.round(1)} Hz")
        end
        
        pitch_data
        
      rescue StandardError => e
        @logger.error("Error parsing Aubio output: #{e.message}")
        raise RuntimeError, "Failed to parse Aubio output: #{e.message}"
      end
    end
  end

  # Sonic Annotator implementation with comprehensive prosodic analysis using pYIN
  #
  # @example Basic usage
  #   analyzer = SonicAnnotatorPitchAnalyzer.new
  #   pitch_data = analyzer.analyze('voice.wav')
  class SonicAnnotatorPitchAnalyzer < PitchAnalyzer
    # @return [String] Vamp plugin identifier
    attr_reader :plugin
    
    # @return [Integer] step size for analysis
    attr_reader :step_size
    
    # @return [Integer] block size for analysis
    attr_reader :block_size
    
    # @return [String] path to transform files directory
    attr_reader :transform_dir

    # Initialize Sonic Annotator pitch analyzer
    #
    # @param plugin [String] Vamp plugin identifier
    # @param step_size [Integer] step size in samples
    # @param block_size [Integer] block size in samples
    # @param logger [Logger, nil] custom logger instance
    # @raise [RuntimeError] if sonic-annotator is not available
    def initialize(plugin: 'pyin:pyin:f0candidates', step_size: 256, block_size: 2048, logger: nil)
      super(logger: logger)
      @plugin = plugin
      @step_size = step_size
      @block_size = block_size
      @transform_dir = File.join(File.dirname(__FILE__), '..', '..', '..', 'transforms')
      
      begin
        @logger.info("Initializing Sonic Annotator analyzer (#{@plugin})")
        ensure_transform_directory
        ensure_all_transforms
        validate_dependencies
        @logger.info("Sonic Annotator analyzer initialized successfully")
      rescue StandardError => e
        @logger.error("Failed to initialize Sonic Annotator analyzer: #{e.message}")
        raise
      end
    end

    # Analyze audio file using Sonic Annotator with comprehensive prosodic analysis
    #
    # @param audio_file [String] path to audio file
    # @return [Array<Hash>] comprehensive pitch and prosodic analysis data
    # @raise [ArgumentError] if audio file is invalid
    # @raise [RuntimeError] if analysis fails
    def analyze(audio_file)
      validate_audio_file(audio_file)
      
      begin
        @logger.info("Starting Sonic Annotator analysis: #{File.basename(audio_file)}")
        start_time = Time.now
        
        # Extract pitch data with timeout
        pitch_data = Timeout.timeout(300) do  # 5 minute timeout
          extract_pitch_data(audio_file)
        end
        @logger.debug("Pitch extraction completed, #{pitch_data.length} data points")
        
        # Extract tempo data with timeout (optional, non-failing)
        tempo_data = Timeout.timeout(180) do  # 3 minute timeout
          extract_tempo_data(audio_file)
        end
        @logger.debug("Tempo extraction completed, #{tempo_data.length} data points")
        
        # Combine results for comprehensive prosodic analysis
        result = combine_analysis_results(pitch_data, tempo_data)
        
        analysis_time = Time.now - start_time
        @logger.info("Sonic Annotator analysis completed in #{analysis_time.round(2)}s")
        
        result
        
      rescue Timeout::Error => e
        error_msg = "Sonic Annotator analysis timed out"
        @logger.error(error_msg)
        raise RuntimeError, error_msg
      rescue StandardError => e
        error_msg = "Sonic Annotator analysis failed: #{e.message}"
        @logger.error(error_msg)
        @logger.debug("Backtrace: #{e.backtrace.join("\n")}")
        raise RuntimeError, error_msg
      end
    end

    # Extract pitch data using pYIN transform
    #
    # @param audio_file [String] path to audio file
    # @return [Array<Hash>] pitch analysis data
    # @raise [RuntimeError] if extraction fails
    def extract_pitch_data(audio_file)
      begin
        transform_file = create_pyin_transform
        @logger.debug("Running pYIN pitch analysis")
        
        stdout, stderr, status = Open3.capture3(
          'sonic-annotator', '-q', 
          '-t', transform_file,
          audio_file,
          '-w', 'csv', '--csv-stdout'
        )

        unless status.success?
          error_msg = "Sonic Annotator pitch analysis failed: #{stderr.strip}"
          @logger.error(error_msg)
          raise RuntimeError, error_msg
        end

        pitch_data = parse_pyin_output(stdout)
        @logger.debug("Extracted #{pitch_data.length} pitch data points")
        pitch_data
        
      rescue StandardError => e
        @logger.error("Failed to extract pitch data: #{e.message}")
        raise RuntimeError, "Pitch data extraction failed: #{e.message}"
      end
    end

    # Extract tempo data using rhythm analysis (optional, non-failing)
    #
    # @param audio_file [String] path to audio file
    # @return [Array<Hash>] tempo analysis data
    def extract_tempo_data(audio_file)
      begin
        transform_file = create_tempo_transform
        @logger.debug("Running tempo/rhythm analysis")
        
        stdout, stderr, status = Open3.capture3(
          'sonic-annotator', '-q',
          '-t', transform_file, 
          audio_file,
          '-w', 'csv', '--csv-stdout'
        )

        # Don't fail if tempo analysis fails - it's supplementary
        unless status.success?
          @logger.warn("Tempo analysis failed (optional): #{stderr.strip}")
          return []
        end
        
        tempo_data = parse_tempo_output(stdout)
        @logger.debug("Extracted #{tempo_data.length} tempo data points")
        tempo_data
        
      rescue StandardError => e
        @logger.warn("Failed to extract tempo data (optional): #{e.message}")
        []  # Return empty array for optional analysis
      end
    end

    private

    # Validate Sonic Annotator dependencies
    #
    # @raise [RuntimeError] if dependencies are missing
    def validate_dependencies
      begin
        stdout, stderr, status = Timeout.timeout(10) do
          Open3.capture3('which', 'sonic-annotator')
        end
        
        unless status.success?
          error_msg = "Sonic Annotator not found. Install from: https://vamp-plugins.org/sonic-annotator/"
          @logger.error(error_msg)
          raise RuntimeError, error_msg
        end
        
        @logger.debug("Sonic Annotator found")
        
        # Check for required Vamp plugins
        check_vamp_plugins
        
      rescue Timeout::Error
        error_msg = "Timeout checking for Sonic Annotator installation"
        @logger.error(error_msg)
        raise RuntimeError, error_msg
      rescue StandardError => e
        error_msg = "Error checking Sonic Annotator installation: #{e.message}"
        @logger.error(error_msg)
        raise RuntimeError, error_msg
      end
    end

    # Check for required Vamp plugins
    #
    # @return [void]
    def check_vamp_plugins
      begin
        stdout, stderr, status = Timeout.timeout(15) do
          Open3.capture3('sonic-annotator', '-l')
        end
        
        unless status.success?
          @logger.warn("Could not list Vamp plugins: #{stderr.strip}")
          return
        end
        
        required_plugins = ['pyin:pyin', 'vamp-example-plugins:fixedtempo']
        missing_plugins = []
        
        required_plugins.each do |plugin|
          unless stdout.include?(plugin)
            missing_plugins << plugin
          end
        end
        
        if missing_plugins.empty?
          @logger.debug("All required Vamp plugins found")
        else
          @logger.warn("Missing Vamp plugins: #{missing_plugins.join(', ')}")
          @logger.warn("Install with your package manager or from: https://vamp-plugins.org/")
        end
        
      rescue Timeout::Error
        @logger.warn("Timeout checking Vamp plugins")
      rescue StandardError => e
        @logger.warn("Error checking Vamp plugins: #{e.message}")
      end
    end

    # Ensure transform directory exists
    #
    # @raise [RuntimeError] if directory cannot be created
    def ensure_transform_directory
      begin
        FileUtils.mkdir_p(@transform_dir)
        @logger.debug("Transform directory ensured: #{@transform_dir}")
      rescue StandardError => e
        error_msg = "Cannot create transform directory #{@transform_dir}: #{e.message}"
        @logger.error(error_msg)
        raise RuntimeError, error_msg
      end
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
  #
  # @example Create an Aubio analyzer
  #   analyzer = PitchAnalyzerFactory.create(backend: :aubio)
  #
  # @example Create a Sonic Annotator analyzer
  #   analyzer = PitchAnalyzerFactory.create(backend: :sonic_annotator, step_size: 128)
  class PitchAnalyzerFactory
    # Create a pitch analyzer instance for the specified backend
    #
    # @param backend [Symbol] pitch analysis backend (:aubio or :sonic_annotator)
    # @param options [Hash] additional options passed to analyzer constructor
    # @return [PitchAnalyzer] configured pitch analyzer instance
    # @raise [ArgumentError] if backend is unknown
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

    # Get list of available pitch analysis backends on the system
    #
    # @return [Array<Symbol>] list of available backends (e.g., [:aubio, :sonic_annotator])
    def self.available_backends
      backends = []
      
      # Check for aubio
      if system('which aubiopitch > /dev/null 2>&1')
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