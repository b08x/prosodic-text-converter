# frozen_string_literal: true

require 'open3'
require 'fileutils'
require 'timeout'

# RDF parsing for Sonic Annotator
require 'rdf'
require 'rdf/turtle'

module ProsodicTextConverter
  # Sonic Annotator implementation with CSV-based output parsing using pYIN
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

    # @return [String] path to vamp plugins directory
    attr_reader :vamp_path

    # Initialize Sonic Annotator pitch analyzer with CSV output
    #
    # @param plugin [String] Vamp plugin identifier
    # @param step_size [Integer] step size in samples
    # @param block_size [Integer] block size in samples
    # @raise [RuntimeError] if sonic-annotator is not available
    def initialize(plugin: 'pyin:pyin:smoothedpitchtrack', step_size: 256, block_size: 2048)
      super()
      @plugin = plugin
      @step_size = step_size
      @block_size = block_size
      @transform_dir = File.join(File.dirname(__FILE__), '..', '..', 'vamp', 'transforms')

      begin
        logger.info("Initializing Sonic Annotator analyzer (#{@plugin})")
        ensure_transform_directory
        validate_dependencies
        ensure_all_transforms
        logger.info('Sonic Annotator analyzer initialized successfully')
      rescue StandardError => e
        logger.error("Failed to initialize Sonic Annotator analyzer: #{e.message}")
        raise
      end
    end

    # Analyze audio file using Sonic Annotator with CSV output
    #
    # @param audio_file [String] path to audio file
    # @return [Array<Hash>] comprehensive pitch and prosodic analysis data
    # @raise [ArgumentError] if audio file is invalid
    # @raise [RuntimeError] if analysis fails
    def analyze(audio_file)
      validate_audio_file(audio_file)

      begin
        logger.info("Starting Sonic Annotator CSV analysis: #{File.basename(audio_file)}")
        start_time = Time.now

        # Extract pitch data with timeout using CSV output
        pitch_data = Timeout.timeout(300) do # 5 minute timeout
          extract_pitch_data_csv(audio_file)
        end
        logger.debug("Pitch extraction completed, #{pitch_data.length} data points")

        # Extract tempo data with timeout (optional, non-failing)
        tempo_data = Timeout.timeout(180) do # 3 minute timeout
          extract_tempo_data_csv(audio_file)
        end
        logger.debug("Tempo extraction completed, #{tempo_data.length} data points")

        # Combine results for comprehensive prosodic analysis
        result = combine_analysis_results(pitch_data, tempo_data)

        analysis_time = Time.now - start_time
        logger.info("Sonic Annotator CSV analysis completed in #{analysis_time.round(2)}s")

        result
      rescue Timeout::Error
        error_msg = 'Sonic Annotator analysis timed out'
        logger.error(error_msg)
        raise error_msg.to_s
      rescue StandardError => e
        error_msg = "Sonic Annotator analysis failed: #{e.message}"
        logger.error(error_msg)
        logger.debug("Backtrace: #{e.backtrace.join("\n")}")
        raise error_msg.to_s
      end
    end

    private

    # Extract pitch data using pYIN transform with CSV output
    #
    # @param audio_file [String] path to audio file
    # @return [Array<Hash>] pitch analysis data
    # @raise [RuntimeError] if extraction fails
    def extract_pitch_data_csv(audio_file)
      transform_file = create_pyin_transform
      logger.debug('Running pYIN pitch analysis with CSV output')

      # Use CSV output format which is more reliable
      env = { 'VAMP_PATH' => @vamp_path }
      stdout, stderr, status = Open3.capture3(
        env,
        'sonic-annotator', '-q',
        '-t', transform_file,
        audio_file,
        '-w', 'csv', '--csv-stdout'
      )

      unless status.success?
        error_msg = "Sonic Annotator pitch analysis failed: #{stderr.strip}"
        logger.error(error_msg)
        raise error_msg.to_s
      end

      pitch_data = parse_csv_output(stdout)
      logger.debug("Extracted #{pitch_data.length} pitch data points from CSV")
      pitch_data
    rescue StandardError => e
      logger.error("Failed to extract pitch data: #{e.message}")
      raise "Pitch data extraction failed: #{e.message}"
    end

    # Extract tempo data using rhythm analysis with CSV output (optional, non-failing)
    #
    # @param audio_file [String] path to audio file
    # @return [Array<Hash>] tempo analysis data
    def extract_tempo_data_csv(audio_file)
      transform_file = create_tempo_transform
      logger.debug('Running tempo/rhythm analysis with CSV output')

      env = { 'VAMP_PATH' => @vamp_path }
      stdout, stderr, status = Open3.capture3(
        env,
        'sonic-annotator', '-q',
        '-t', transform_file,
        audio_file,
        '-w', 'csv', '--csv-stdout'
      )

      # Don't fail if tempo analysis fails - it's supplementary
      unless status.success?
        logger.warn("Tempo analysis failed (optional): #{stderr.strip}")
        return []
      end

      tempo_data = parse_tempo_csv_output(stdout)
      logger.debug("Extracted #{tempo_data.length} tempo data points from CSV")
      tempo_data
    rescue StandardError => e
      logger.warn("Failed to extract tempo data (optional): #{e.message}")
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
        logger.error(error_msg)
        raise error_msg.to_s
      end

      logger.debug('Sonic Annotator found')

      # Set VAMP_PATH to system directories or environment variable
      @vamp_path = ENV['VAMP_PATH'] || '/usr/local/share/vamp:/usr/lib/vamp'
      ENV['VAMP_PATH'] = @vamp_path

      # Check for required Vamp plugins
      check_vamp_plugins
    rescue Timeout::Error
      error_msg = 'Timeout checking for Sonic Annotator installation'
      logger.error(error_msg)
      raise error_msg.to_s
    rescue StandardError => e
      error_msg = "Error checking Sonic Annotator installation: #{e.message}"
      logger.error(error_msg)
      raise error_msg.to_s
    end

    # Check for required Vamp plugins
    #
    # @return [void]
    def check_vamp_plugins
      env = { 'VAMP_PATH' => @vamp_path }
      stdout, stderr, status = Timeout.timeout(15) do
        Open3.capture3(env, 'sonic-annotator', '-l')
      end

      unless status.success?
        logger.warn("Could not list Vamp plugins: #{stderr.strip}")
        return
      end

      required_plugins = ['pyin:pyin', 'vamp-example-plugins:fixedtempo']
      missing_plugins = []

      required_plugins.each do |plugin|
        missing_plugins << plugin unless stdout.include?(plugin)
      end

      if missing_plugins.empty?
        logger.debug('All required Vamp plugins found')
      else
        logger.warn("Missing Vamp plugins: #{missing_plugins.join(', ')}")
        logger.warn('Install with your package manager or from: https://vamp-plugins.org/')
      end
    rescue Timeout::Error
      logger.warn('Timeout checking Vamp plugins')
    rescue StandardError => e
      logger.warn("Error checking Vamp plugins: #{e.message}")
    end

    # Parse CSV output for pitch data
    #
    # @param csv_output [String] CSV formatted output from Sonic Annotator
    # @return [Array<Hash>] parsed pitch data
    def parse_csv_output(csv_output)
      pitch_data = []

      csv_output.each_line do |line|
        line = line.strip
        next if line.empty?

        # Parse CSV line: "filename",timestamp,frequency
        parts = line.split(',')
        next unless parts.length >= 3

        begin
          timestamp = parts[1].to_f
          frequency = parts[2].to_f

          # Filter reasonable speech range and non-zero values
          next unless frequency >= 50.0 && frequency <= 800.0

          pitch_data << {
            timestamp: timestamp,
            frequency: frequency,
            confidence: 1.0 # pYIN provides high-confidence smoothed output
          }
        rescue StandardError => e
          logger.warn("Skipping invalid CSV line: #{line} (#{e.message})")
          next
        end
      end

      # Sort by timestamp
      pitch_data.sort_by! { |point| point[:timestamp] }
      pitch_data
    end

    # Parse CSV output for tempo data
    #
    # @param csv_output [String] CSV formatted output from Sonic Annotator
    # @return [Array<Hash>] parsed tempo data
    def parse_tempo_csv_output(csv_output)
      tempo_data = []

      csv_output.each_line do |line|
        line = line.strip
        next if line.empty?

        # Parse CSV line: "filename",timestamp,value
        parts = line.split(',')
        next unless parts.length >= 3

        begin
          timestamp = parts[1].to_f
          tempo = parts[2].to_f

          next unless tempo > 0

          tempo_data << {
            timestamp: timestamp,
            tempo: tempo
          }
        rescue StandardError => e
          logger.warn("Skipping invalid tempo CSV line: #{line} (#{e.message})")
          next
        end
      end

      # Sort by timestamp
      tempo_data.sort_by! { |point| point[:timestamp] }
      tempo_data
    end

    # Ensure transform directory exists
    #
    # @raise [RuntimeError] if directory cannot be created
    def ensure_transform_directory
      FileUtils.mkdir_p(@transform_dir)
      logger.debug("Transform directory ensured: #{@transform_dir}")
    rescue StandardError => e
      error_msg = "Cannot create transform directory #{@transform_dir}: #{e.message}"
      logger.error(error_msg)
      raise error_msg.to_s
    end

    def ensure_all_transforms
      # Create all transform files programmatically using skeleton generation
      create_pyin_transform
      create_tempo_transform
    end

    def create_pyin_transform
      transform_file = File.join(@transform_dir, 'pyin_pitch.n3')

      # Generate proper transform file using sonic-annotator skeleton
      env = { 'VAMP_PATH' => @vamp_path }
      stdout, stderr, status = Open3.capture3(
        env,
        'sonic-annotator', '-s', 'vamp:pyin:pyin:smoothedpitchtrack'
      )

      unless status.success?
        error_msg = "Failed to generate pyin transform: #{stderr.strip}"
        logger.error(error_msg)
        raise error_msg.to_s
      end

      File.write(transform_file, stdout)
      logger.debug("Generated pyin transform: #{transform_file}")
      transform_file
    end

    def create_tempo_transform
      transform_file = File.join(@transform_dir, 'tempo.n3')

      # Generate proper transform file using sonic-annotator skeleton
      env = { 'VAMP_PATH' => @vamp_path }
      stdout, stderr, status = Open3.capture3(
        env,
        'sonic-annotator', '-s', 'vamp:vamp-example-plugins:fixedtempo:tempo'
      )

      unless status.success?
        error_msg = "Failed to generate tempo transform: #{stderr.strip}"
        logger.error(error_msg)
        raise error_msg.to_s
      end

      File.write(transform_file, stdout)
      logger.debug("Generated tempo transform: #{transform_file}")
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
