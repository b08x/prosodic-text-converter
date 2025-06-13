# frozen_string_literal: true

require 'spec_helper'
require 'prosodic-text-converter/core/config'

RSpec.describe ProsodicTextConverter::Config, 'Speech Pattern Configuration' do
  let(:config_dir) { File.join(__dir__, '..', 'test_files', 'config') }
  let(:test_config_file) { File.join(config_dir, 'defaults.yml') }
  let(:config) { described_class.new(config_dir: config_dir) }

  before do
    # Create test config directory
    FileUtils.mkdir_p(config_dir) unless Dir.exist?(config_dir)
    
    # Create test config file with speech pattern options
    File.write(test_config_file, test_config_yaml)
    
    # Clear environment variables
    clear_speech_pattern_env_vars
  end

  after do
    # Clean up test files
    FileUtils.rm_rf(config_dir) if Dir.exist?(config_dir)
    
    # Clear environment variables
    clear_speech_pattern_env_vars
  end

  describe 'speech pattern analysis configuration' do
    describe '#speech_pattern_analysis_enabled?' do
      it 'returns default value when not configured' do
        expect(config.speech_pattern_analysis_enabled?).to be(false)
      end

      it 'returns configured value from YAML' do
        write_config_with(enable_speech_pattern_analysis: true)
        test_config = described_class.new(config_dir: config_dir)
        expect(test_config.speech_pattern_analysis_enabled?).to be(true)
      end

      it 'returns environment variable value' do
        ENV['PTC_ENABLE_SPEECH_PATTERN_ANALYSIS'] = 'true'
        test_config = described_class.new(config_dir: config_dir)
        expect(test_config.speech_pattern_analysis_enabled?).to be(true)
      end
    end

    describe '#speech_pattern_rewriting_enabled?' do
      it 'returns default value when not configured' do
        expect(config.speech_pattern_rewriting_enabled?).to be(false)
      end

      it 'returns configured value from YAML' do
        write_config_with(speech_pattern_rewriting: true)
        test_config = described_class.new(config_dir: config_dir)
        expect(test_config.speech_pattern_rewriting_enabled?).to be(true)
      end

      it 'returns environment variable value' do
        ENV['PTC_SPEECH_PATTERN_REWRITING'] = 'true'
        test_config = described_class.new(config_dir: config_dir)
        expect(test_config.speech_pattern_rewriting_enabled?).to be(true)
      end
    end

    describe '#pattern_analysis_timeout' do
      it 'returns default timeout' do
        expect(config.pattern_analysis_timeout).to eq(120)
      end

      it 'returns configured timeout from YAML' do
        write_config_with(pattern_analysis_timeout: 180)
        test_config = described_class.new(config_dir: config_dir)
        expect(test_config.pattern_analysis_timeout).to eq(180)
      end

      it 'returns environment variable timeout' do
        ENV['PTC_PATTERN_ANALYSIS_TIMEOUT'] = '240'
        test_config = described_class.new(config_dir: config_dir)
        expect(test_config.pattern_analysis_timeout).to eq(240)
      end
    end
  end

  describe 'rewriting strategy configuration' do
    describe '#rewrite_strategy' do
      it 'returns default strategy' do
        expect(config.rewrite_strategy).to eq('hybrid')
      end

      it 'returns configured strategy from YAML' do
        write_config_with(rewrite_strategy: 'rhythm')
        test_config = described_class.new(config_dir: config_dir)
        expect(test_config.rewrite_strategy).to eq('rhythm')
      end

      it 'accepts valid strategies' do
        valid_strategies = ['rhythm', 'stress', 'intonation', 'hybrid', 'comprehensive']
        
        valid_strategies.each do |strategy|
          write_config_with(rewrite_strategy: strategy)
          test_config = described_class.new(config_dir: config_dir)
          expect(test_config.rewrite_strategy).to eq(strategy)
        end
      end
    end

    describe '#pattern_rewrite_aggressiveness' do
      it 'returns default aggressiveness' do
        expect(config.pattern_rewrite_aggressiveness).to eq('medium')
      end

      it 'returns configured aggressiveness from YAML' do
        write_config_with(pattern_rewrite_aggressiveness: 'aggressive')
        test_config = described_class.new(config_dir: config_dir)
        expect(test_config.pattern_rewrite_aggressiveness).to eq('aggressive')
      end

      it 'accepts valid aggressiveness levels' do
        valid_levels = ['conservative', 'medium', 'aggressive']
        
        valid_levels.each do |level|
          write_config_with(pattern_rewrite_aggressiveness: level)
          test_config = described_class.new(config_dir: config_dir)
          expect(test_config.pattern_rewrite_aggressiveness).to eq(level)
        end
      end
    end

    describe '#pattern_meaning_threshold' do
      it 'returns default threshold' do
        expect(config.pattern_meaning_threshold).to eq(0.85)
      end

      it 'returns configured threshold from YAML' do
        write_config_with(pattern_meaning_threshold: 0.9)
        test_config = described_class.new(config_dir: config_dir)
        expect(test_config.pattern_meaning_threshold).to eq(0.9)
      end

      it 'accepts threshold from environment' do
        ENV['PTC_PATTERN_MEANING_THRESHOLD'] = '0.75'
        test_config = described_class.new(config_dir: config_dir)
        expect(test_config.pattern_meaning_threshold).to eq(0.75)
      end
    end
  end

  describe 'pattern analysis feature configuration' do
    describe '#emotional_detection_enabled?' do
      it 'returns default value' do
        expect(config.emotional_detection_enabled?).to be(true)
      end

      it 'returns configured value from YAML' do
        write_config_with(enable_emotional_detection: false)
        test_config = described_class.new(config_dir: config_dir)
        expect(test_config.emotional_detection_enabled?).to be(false)
      end
    end

    describe '#detailed_pattern_analysis_enabled?' do
      it 'returns default value' do
        expect(config.detailed_pattern_analysis_enabled?).to be(true)
      end

      it 'returns configured value from YAML' do
        write_config_with(detailed_pattern_analysis: false)
        test_config = described_class.new(config_dir: config_dir)
        expect(test_config.detailed_pattern_analysis_enabled?).to be(false)
      end
    end

    describe '#rhythm_sensitivity' do
      it 'returns default sensitivity' do
        expect(config.rhythm_sensitivity).to eq(0.7)
      end

      it 'returns configured sensitivity from YAML' do
        write_config_with(rhythm_sensitivity: 0.5)
        test_config = described_class.new(config_dir: config_dir)
        expect(test_config.rhythm_sensitivity).to eq(0.5)
      end

      it 'accepts valid sensitivity range' do
        [0.1, 0.5, 0.8, 1.0].each do |sensitivity|
          write_config_with(rhythm_sensitivity: sensitivity)
          test_config = described_class.new(config_dir: config_dir)
          expect(test_config.rhythm_sensitivity).to eq(sensitivity)
        end
      end
    end

    describe '#stress_detection_threshold' do
      it 'returns default threshold' do
        expect(config.stress_detection_threshold).to eq(0.6)
      end

      it 'returns configured threshold from YAML' do
        write_config_with(stress_detection_threshold: 0.8)
        test_config = described_class.new(config_dir: config_dir)
        expect(test_config.stress_detection_threshold).to eq(0.8)
      end
    end

    describe '#intonation_smoothing' do
      it 'returns default smoothing factor' do
        expect(config.intonation_smoothing).to eq(0.3)
      end

      it 'returns configured smoothing from YAML' do
        write_config_with(intonation_smoothing: 0.5)
        test_config = described_class.new(config_dir: config_dir)
        expect(test_config.intonation_smoothing).to eq(0.5)
      end
    end
  end

  describe 'iterative refinement configuration' do
    describe '#iterative_pattern_refinement_enabled?' do
      it 'returns default value' do
        expect(config.iterative_pattern_refinement_enabled?).to be(true)
      end

      it 'returns configured value from YAML' do
        write_config_with(iterative_pattern_refinement: false)
        test_config = described_class.new(config_dir: config_dir)
        expect(test_config.iterative_pattern_refinement_enabled?).to be(false)
      end
    end

    describe '#max_rewrite_iterations' do
      it 'returns default iterations' do
        expect(config.max_rewrite_iterations).to eq(3)
      end

      it 'returns configured iterations from YAML' do
        write_config_with(max_rewrite_iterations: 5)
        test_config = described_class.new(config_dir: config_dir)
        expect(test_config.max_rewrite_iterations).to eq(5)
      end

      it 'accepts reasonable iteration limits' do
        [1, 3, 5, 10].each do |iterations|
          write_config_with(max_rewrite_iterations: iterations)
          test_config = described_class.new(config_dir: config_dir)
          expect(test_config.max_rewrite_iterations).to eq(iterations)
        end
      end
    end
  end

  describe 'configuration option bundles' do
    describe '#speech_pattern_extractor_options' do
      it 'returns appropriate options hash' do
        options = config.speech_pattern_extractor_options

        expect(options).to be_a(Hash)
        expect(options).to have_key(:detailed_analysis)
        expect(options).to have_key(:emotional_detection)
        expect(options).to have_key(:rhythm_sensitivity)
        expect(options).to have_key(:stress_detection_threshold)
        expect(options).to have_key(:intonation_smoothing)

        expect(options[:detailed_analysis]).to be(true)
        expect(options[:emotional_detection]).to be(true)
        expect(options[:rhythm_sensitivity]).to eq(0.7)
        expect(options[:stress_detection_threshold]).to eq(0.6)
        expect(options[:intonation_smoothing]).to eq(0.3)
      end

      it 'reflects configured values' do
        write_config_with(
          detailed_pattern_analysis: false,
          enable_emotional_detection: false,
          rhythm_sensitivity: 0.5,
          stress_detection_threshold: 0.8,
          intonation_smoothing: 0.4
        )
        
        test_config = described_class.new(config_dir: config_dir)
        options = test_config.speech_pattern_extractor_options

        expect(options[:detailed_analysis]).to be(false)
        expect(options[:emotional_detection]).to be(false)
        expect(options[:rhythm_sensitivity]).to eq(0.5)
        expect(options[:stress_detection_threshold]).to eq(0.8)
        expect(options[:intonation_smoothing]).to eq(0.4)
      end
    end

    describe '#speech_pattern_rewriter_options' do
      it 'returns appropriate options hash' do
        options = config.speech_pattern_rewriter_options

        expect(options).to be_a(Hash)
        expect(options).to have_key(:rewrite_strategy)
        expect(options).to have_key(:preserve_meaning)
        expect(options).to have_key(:meaning_threshold)
        expect(options).to have_key(:detailed_logging)
        expect(options).to have_key(:max_iterations)
        expect(options).to have_key(:iterative_refinement)
        expect(options).to have_key(:timeout)

        expect(options[:rewrite_strategy]).to eq('hybrid')
        expect(options[:preserve_meaning]).to be(true)
        expect(options[:meaning_threshold]).to eq(0.85)
        expect(options[:detailed_logging]).to be(true)
        expect(options[:max_iterations]).to eq(3)
        expect(options[:iterative_refinement]).to be(true)
        expect(options[:timeout]).to eq(120)
      end

      it 'reflects configured values' do
        write_config_with(
          rewrite_strategy: 'stress',
          pattern_meaning_threshold: 0.9,
          max_rewrite_iterations: 5,
          iterative_pattern_refinement: false,
          pattern_analysis_timeout: 180
        )
        
        test_config = described_class.new(config_dir: config_dir)
        options = test_config.speech_pattern_rewriter_options

        expect(options[:rewrite_strategy]).to eq('stress')
        expect(options[:meaning_threshold]).to eq(0.9)
        expect(options[:max_iterations]).to eq(5)
        expect(options[:iterative_refinement]).to be(false)
        expect(options[:timeout]).to eq(180)
      end
    end
  end

  describe 'CLI argument parsing' do
    it 'parses speech pattern flags' do
      args = [
        '--enable-speech-patterns',
        '--enable-pattern-rewriting',
        '--rewrite-strategy=rhythm',
        '--pattern-rewrite-aggressiveness=aggressive',
        '--pattern-meaning-threshold=0.9',
        '--enable-emotional-detection',
        '--rhythm-sensitivity=0.8',
        '--max-rewrite-iterations=5'
      ]
      
      test_config = described_class.from_cli_args(args, config_dir: config_dir)
      
      expect(test_config.speech_pattern_analysis_enabled?).to be(true)
      expect(test_config.speech_pattern_rewriting_enabled?).to be(true)
      expect(test_config.rewrite_strategy).to eq('rhythm')
      expect(test_config.pattern_rewrite_aggressiveness).to eq('aggressive')
      expect(test_config.pattern_meaning_threshold).to eq(0.9)
      expect(test_config.emotional_detection_enabled?).to be(true)
      expect(test_config.rhythm_sensitivity).to eq(0.8)
      expect(test_config.max_rewrite_iterations).to eq(5)
    end

    it 'parses disable flags' do
      args = [
        '--disable-speech-patterns',
        '--disable-pattern-rewriting',
        '--disable-emotional-detection',
        '--disable-detailed-analysis',
        '--disable-iterative-refinement'
      ]
      
      test_config = described_class.from_cli_args(args, config_dir: config_dir)
      
      expect(test_config.speech_pattern_analysis_enabled?).to be(false)
      expect(test_config.speech_pattern_rewriting_enabled?).to be(false)
      expect(test_config.emotional_detection_enabled?).to be(false)
      expect(test_config.detailed_pattern_analysis_enabled?).to be(false)
      expect(test_config.iterative_pattern_refinement_enabled?).to be(false)
    end

    it 'parses numeric parameters correctly' do
      args = [
        '--pattern-analysis-timeout=240',
        '--stress-threshold=0.7',
        '--intonation-smoothing=0.4'
      ]
      
      test_config = described_class.from_cli_args(args, config_dir: config_dir)
      
      expect(test_config.pattern_analysis_timeout).to eq(240)
      expect(test_config.stress_detection_threshold).to eq(0.7)
      expect(test_config.intonation_smoothing).to eq(0.4)
    end
  end

  describe 'environment variable precedence' do
    it 'prioritizes environment variables over YAML config' do
      write_config_with(
        enable_speech_pattern_analysis: false,
        rewrite_strategy: 'rhythm',
        pattern_meaning_threshold: 0.7
      )
      
      ENV['PTC_ENABLE_SPEECH_PATTERN_ANALYSIS'] = 'true'
      ENV['PTC_REWRITE_STRATEGY'] = 'stress'
      ENV['PTC_PATTERN_MEANING_THRESHOLD'] = '0.9'
      
      test_config = described_class.new(config_dir: config_dir)
      
      expect(test_config.speech_pattern_analysis_enabled?).to be(true)
      expect(test_config.rewrite_strategy).to eq('stress')
      expect(test_config.pattern_meaning_threshold).to eq(0.9)
    end

    it 'prioritizes CLI args over environment variables' do
      ENV['PTC_ENABLE_SPEECH_PATTERN_ANALYSIS'] = 'false'
      ENV['PTC_REWRITE_STRATEGY'] = 'rhythm'
      
      args = ['--enable-speech-patterns', '--rewrite-strategy=intonation']
      test_config = described_class.from_cli_args(args, config_dir: config_dir)
      
      expect(test_config.speech_pattern_analysis_enabled?).to be(true)
      expect(test_config.rewrite_strategy).to eq('intonation')
    end
  end

  describe 'configuration validation' do
    it 'handles invalid numeric values gracefully' do
      # Test with YAML config
      write_config_with(rhythm_sensitivity: 'invalid')
      test_config = described_class.new(config_dir: config_dir)
      
      # Should fall back to default
      expect(test_config.rhythm_sensitivity).to eq(0.7)
    end

    it 'handles missing config file gracefully' do
      FileUtils.rm_f(test_config_file)
      test_config = described_class.new(config_dir: config_dir)
      
      # Should use defaults
      expect(test_config.speech_pattern_analysis_enabled?).to be(false)
      expect(test_config.rewrite_strategy).to eq('hybrid')
      expect(test_config.pattern_meaning_threshold).to eq(0.85)
    end
  end

  private

  def test_config_yaml
    <<~YAML
      # Test configuration for speech patterns
      provider: "gemini"
      model: "gemini-2.0-flash"
      pitch_backend: "aubio"
      
      # Speech Pattern Configuration
      enable_speech_pattern_analysis: false
      speech_pattern_rewriting: false
      pattern_analysis_timeout: 120
      rewrite_strategy: "hybrid"
      pattern_rewrite_aggressiveness: "medium"
      pattern_meaning_threshold: 0.85
      enable_emotional_detection: true
      detailed_pattern_analysis: true
      rhythm_sensitivity: 0.7
      stress_detection_threshold: 0.6
      intonation_smoothing: 0.3
      iterative_pattern_refinement: true
      max_rewrite_iterations: 3
    YAML
  end

  def write_config_with(options)
    config_hash = {
      'provider' => 'gemini',
      'model' => 'gemini-2.0-flash',
      'pitch_backend' => 'aubio'
    }.merge(options.transform_keys(&:to_s))
    
    File.write(test_config_file, config_hash.to_yaml)
  end

  def clear_speech_pattern_env_vars
    speech_pattern_env_vars.each { |var| ENV.delete(var) }
  end

  def speech_pattern_env_vars
    %w[
      PTC_ENABLE_SPEECH_PATTERN_ANALYSIS
      PTC_SPEECH_PATTERN_REWRITING
      PTC_PATTERN_ANALYSIS_TIMEOUT
      PTC_REWRITE_STRATEGY
      PTC_PATTERN_REWRITE_AGGRESSIVENESS
      PTC_PATTERN_MEANING_THRESHOLD
      PTC_ENABLE_EMOTIONAL_DETECTION
      PTC_DETAILED_PATTERN_ANALYSIS
      PTC_RHYTHM_SENSITIVITY
      PTC_STRESS_DETECTION_THRESHOLD
      PTC_INTONATION_SMOOTHING
      PTC_ITERATIVE_PATTERN_REFINEMENT
      PTC_MAX_REWRITE_ITERATIONS
    ]
  end
end