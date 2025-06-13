# frozen_string_literal: true

require 'open3'
require 'fileutils'
require 'logger'
require 'timeout'

# RDF parsing for Sonic Annotator
require 'rdf'
require 'rdf/turtle'

module ProsodicTextConverter
  # Sonic Annotator implementation with RDF-based output parsing using pYIN
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

    # Initialize Sonic Annotator pitch analyzer with RDF output
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
        @logger.info('Sonic Annotator analyzer initialized successfully')
      rescue StandardError => e
        @logger.error("Failed to initialize Sonic Annotator analyzer: #{e.message}")
        raise
      end
    end

    # Analyze audio file using Sonic Annotator with RDF output
    #
    # @param audio_file [String] path to audio file
    # @return [Array<Hash>] comprehensive pitch and prosodic analysis data
    # @raise [ArgumentError] if audio file is invalid
    # @raise [RuntimeError] if analysis fails
    def analyze(audio_file)
      validate_audio_file(audio_file)

      begin
        @logger.info("Starting Sonic Annotator RDF analysis: #{File.basename(audio_file)}")
        start_time = Time.now

        # Extract pitch data with timeout using RDF output
        pitch_data = Timeout.timeout(300) do # 5 minute timeout
          extract_pitch_data_rdf(audio_file)
        end
        @logger.debug("Pitch extraction completed, #{pitch_data.length} data points")

        # Extract tempo data with timeout (optional, non-failing)
        tempo_data = Timeout.timeout(180) do # 3 minute timeout
          extract_tempo_data_rdf(audio_file)
        end
        @logger.debug("Tempo extraction completed, #{tempo_data.length} data points")

        # Combine results for comprehensive prosodic analysis
        result = combine_analysis_results(pitch_data, tempo_data)

        analysis_time = Time.now - start_time
        @logger.info("Sonic Annotator RDF analysis completed in #{analysis_time.round(2)}s")

        result
      rescue Timeout::Error
        error_msg = 'Sonic Annotator analysis timed out'
        @logger.error(error_msg)
        raise error_msg.to_s
      rescue StandardError => e
        error_msg = "Sonic Annotator analysis failed: #{e.message}"
        @logger.error(error_msg)
        @logger.debug("Backtrace: #{e.backtrace.join("\n")}")
        raise error_msg.to_s
      end
    end

    private

    # Extract pitch data using pYIN transform with RDF output
    #
    # @param audio_file [String] path to audio file
    # @return [Array<Hash>] pitch analysis data
    # @raise [RuntimeError] if extraction fails
    def extract_pitch_data_rdf(audio_file)
      transform_file = create_pyin_transform
      @logger.debug('Running pYIN pitch analysis with RDF output')

      # Use RDF output format instead of CSV
      stdout, stderr, status = Open3.capture3(
        'sonic-annotator', '-q',
        '-t', transform_file,
        audio_file,
        '-w', 'rdf'
      )

      unless status.success?
        error_msg = "Sonic Annotator pitch analysis failed: #{stderr.strip}"
        @logger.error(error_msg)
        raise error_msg.to_s
      end

      pitch_data = parse_rdf_output(stdout)
      @logger.debug("Extracted #{pitch_data.length} pitch data points from RDF")
      pitch_data
    rescue StandardError => e
      @logger.error("Failed to extract pitch data: #{e.message}")
      raise "Pitch data extraction failed: #{e.message}"
    end

    # Extract tempo data using rhythm analysis with RDF output (optional, non-failing)
    #
    # @param audio_file [String] path to audio file
    # @return [Array<Hash>] tempo analysis data
    def extract_tempo_data_rdf(audio_file)
      transform_file = create_tempo_transform
      @logger.debug('Running tempo/rhythm analysis with RDF output')

      stdout, stderr, status = Open3.capture3(
        'sonic-annotator', '-q',
        '-t', transform_file,
        audio_file,
        '-w', 'rdf'
      )

      # Don't fail if tempo analysis fails - it's supplementary
      unless status.success?
        @logger.warn("Tempo analysis failed (optional): #{stderr.strip}")
        return []
      end

      tempo_data = parse_tempo_rdf_output(stdout)
      @logger.debug("Extracted #{tempo_data.length} tempo data points from RDF")
      tempo_data
    rescue StandardError => e
      @logger.warn("Failed to extract tempo data (optional): #{e.message}")
      [] # Return empty array for optional analysis
    end

    # Validate Sonic Annotator dependencies
    #
    # @raise [RuntimeError] if dependencies are missing
    def validate_dependencies
      _, _, status = Timeout.timeout(10) do
        Open3.capture3('which', 'sonic-annotator')
      end

      unless status.success?
        error_msg = 'Sonic Annotator not found. Install from: https://vamp-plugins.org/sonic-annotator/'
        @logger.error(error_msg)
        raise error_msg.to_s
      end

      @logger.debug('Sonic Annotator found')

      # Check for required Vamp plugins
      check_vamp_plugins
    rescue Timeout::Error
      error_msg = 'Timeout checking for Sonic Annotator installation'
      @logger.error(error_msg)
      raise error_msg.to_s
    rescue StandardError => e
      error_msg = "Error checking Sonic Annotator installation: #{e.message}"
      @logger.error(error_msg)
      raise error_msg.to_s
    end

    # Check for required Vamp plugins
    #
    # @return [void]
    def check_vamp_plugins
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
        missing_plugins << plugin unless stdout.include?(plugin)
      end

      if missing_plugins.empty?
        @logger.debug('All required Vamp plugins found')
      else
        @logger.warn("Missing Vamp plugins: #{missing_plugins.join(', ')}")
        @logger.warn('Install with your package manager or from: https://vamp-plugins.org/')
      end
    rescue Timeout::Error
      @logger.warn('Timeout checking Vamp plugins')
    rescue StandardError => e
      @logger.warn("Error checking Vamp plugins: #{e.message}")
    end

    # Parse RDF output for pitch data
    #
    # @param rdf_output [String] RDF/Turtle formatted output from Sonic Annotator
    # @return [Array<Hash>] parsed pitch data
    def parse_rdf_output(rdf_output)
      pitch_data = []

      begin
        # Parse the RDF graph
        graph = RDF::Graph.new
        RDF::Turtle::Reader.new(rdf_output) do |reader|
          reader.each_statement do |statement|
            graph << statement
          end
        end

        # Query for pitch data using VAMP ontology
        # Look for events with time and value properties
        graph.each_statement do |stmt|
          # Find events that have time and pitch values
          next unless stmt.predicate.to_s.include?('time') || stmt.predicate.to_s.include?('value')

          event_uri = stmt.subject

          # Get timestamp
          time_query = graph.query([event_uri, :predicate, :object]).select do |s|
            s.predicate.to_s.include?('time')
          end

          # Get frequency value
          value_query = graph.query([event_uri, :predicate, :object]).select do |s|
            s.predicate.to_s.include?('value')
          end

          next unless !time_query.empty? && !value_query.empty?

          timestamp = time_query.first.object.to_f
          frequency = value_query.first.object.to_f

          # Filter reasonable speech range and non-zero values
          next unless frequency >= 50.0 && frequency <= 800.0

          pitch_data << {
            timestamp: timestamp,
            frequency: frequency,
            confidence: 1.0 # pYIN provides high-confidence smoothed output
          }
        end

        # Sort by timestamp
        pitch_data.sort_by! { |point| point[:timestamp] }
      rescue StandardError => e
        @logger.error("Error parsing RDF output: #{e.message}")
        # Fallback to empty array
        pitch_data = []
      end

      pitch_data
    end

    # Parse RDF output for tempo data
    #
    # @param rdf_output [String] RDF/Turtle formatted output from Sonic Annotator
    # @return [Array<Hash>] parsed tempo data
    def parse_tempo_rdf_output(rdf_output)
      tempo_data = []

      begin
        # Parse the RDF graph
        graph = RDF::Graph.new
        RDF::Turtle::Reader.new(rdf_output) do |reader|
          reader.each_statement do |statement|
            graph << statement
          end
        end

        # Query for tempo events
        graph.each_statement do |stmt|
          next unless stmt.predicate.to_s.include?('time') || stmt.predicate.to_s.include?('value')

          event_uri = stmt.subject

          # Get timestamp
          time_query = graph.query([event_uri, :predicate, :object]).select do |s|
            s.predicate.to_s.include?('time')
          end

          # Get tempo value
          value_query = graph.query([event_uri, :predicate, :object]).select do |s|
            s.predicate.to_s.include?('value')
          end

          next unless !time_query.empty? && !value_query.empty?

          timestamp = time_query.first.object.to_f
          tempo = value_query.first.object.to_f

          next unless tempo > 0

          tempo_data << {
            timestamp: timestamp,
            tempo: tempo
          }
        end

        # Sort by timestamp
        tempo_data.sort_by! { |point| point[:timestamp] }
      rescue StandardError => e
        @logger.error("Error parsing tempo RDF output: #{e.message}")
        tempo_data = []
      end

      tempo_data
    end

    # Ensure transform directory exists
    #
    # @raise [RuntimeError] if directory cannot be created
    def ensure_transform_directory
      FileUtils.mkdir_p(@transform_dir)
      @logger.debug("Transform directory ensured: #{@transform_dir}")
    rescue StandardError => e
      error_msg = "Cannot create transform directory #{@transform_dir}: #{e.message}"
      @logger.error(error_msg)
      raise error_msg.to_s
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
            vamp:step_size "#{@step_size}"^^xsd:int ;#{' '}
            vamp:block_size "#{@block_size}"^^xsd:int ;#{' '}
            vamp:plugin_version """3""" ;#{' '}
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
            vamp:step_size "512"^^xsd:int ;#{' '}
            vamp:block_size "2048"^^xsd:int ;#{' '}
            vamp:plugin_version """4""" ;#{' '}
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
end
