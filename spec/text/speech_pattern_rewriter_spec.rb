# frozen_string_literal: true

require 'spec_helper'
require 'prosodic-text-converter/text/speech_pattern_rewriter'
require 'prosodic-text-converter/text/text_analyzer'
require 'prosodic-text-converter/conversion/llm_converter'

RSpec.describe ProsodicTextConverter::SpeechPatternRewriter do
  let(:provider) { :gemini }
  let(:model) { 'gemini-2.5-flash' }
  let(:rewriter) { described_class.new(provider: provider, model: model) }
  let(:text_analyzer) { ProsodicTextConverter::TextAnalyzer.new }
  let(:sample_text) { 'Hello world. This is a test sentence for speech pattern rewriting.' }
  let(:text_analysis) { text_analyzer.analyze(sample_text) }

  let(:mock_rewrite_guidance) do
    {
      overall_strategy: {
        primary_focus: 'rhythm',
        rewrite_aggressiveness: 'medium',
        rhythm_priority: 'high',
        stress_priority: 'medium',
        intonation_priority: 'low'
      },
      sentence_guidance: [
        {
          sentence_index: 0,
          original_text: 'Hello world.',
          recommended_changes: [
            {
              type: 'rhythm_adjustment',
              reason: 'improve_flow',
              suggestion: 'Consider adding pause markers'
            }
          ],
          target_timing: {
            target_duration: 1.5,
            recommended_pauses: 1,
            timing_flexibility: 'medium'
          }
        }
      ],
      rhythm_adjustments: {
        target_tempo: 120,
        rhythm_type: 'regular',
        adjustments: []
      },
      stress_adjustments: {
        stress_pattern: 'iambic',
        stress_density: 0.6,
        adjustments: []
      },
      intonation_guidance: {
        available: true,
        contour_shape: 'rising',
        boundary_tones: { initial: 150.0, final: 160.0 }
      },
      pacing_recommendations: {
        overall_pace: 'medium',
        segment_pacing: [],
        pause_strategy: 'maintain_pauses'
      },
      emotional_alignment: {
        available: false
      },
      prosodic_targets: {
        rhythm_target: { tempo: 120, regularity: 'regular' },
        stress_target: { pattern: 'iambic', density: 0.6 }
      }
    }
  end

  let(:mock_llm_response) do
    double('LLMResponse',
           content: 'Hello there, world. This is an improved test sentence for speech pattern rewriting.')
  end

  let(:mock_llm_client) do
    double('LLMClient').tap do |client|
      allow(client).to receive(:with_model).and_return(client)
      allow(client).to receive(:with_temperature).and_return(client)
      allow(client).to receive(:ask).and_return(mock_llm_response)
    end
  end

  before do
    # Mock the LLM converter
    mock_converter = double('LLMConverter')
    allow(mock_converter).to receive(:model).and_return(model)
    allow(mock_converter).to receive(:instance_variable_get).with(:@client).and_return(mock_llm_client)
    allow(ProsodicTextConverter::LLMConverter).to receive(:new).and_return(mock_converter)
  end

  describe '#initialize' do
    it 'initializes with default options' do
      expect(rewriter).to be_a(described_class)
      expect(rewriter.llm_converter).to respond_to(:model)
    end

    it 'accepts custom options' do
      custom_rewriter = described_class.new(
        provider: :openai,
        model: 'gpt-4',
        rewrite_strategy: 'comprehensive',
        preserve_meaning: false,
        meaning_threshold: 0.7
      )
      expect(custom_rewriter).to be_a(described_class)
    end

    it 'raises error on initialization failure' do
      allow(ProsodicTextConverter::LLMConverter).to receive(:new).and_raise(StandardError.new('Init failed'))

      expect do
        described_class.new(provider: provider, model: model)
      end.to raise_error(/Failed to initialize SpeechPatternRewriter/)
    end
  end

  describe '#rewrite_text' do
    it 'successfully rewrites text using speech patterns' do
      result = rewriter.rewrite_text(text_analysis, mock_rewrite_guidance)

      expect(result).to be_a(Hash)
      expect(result).to have_key(:rewritten_text)
      expect(result).to have_key(:rewritten_analysis)
      expect(result).to have_key(:rewrite_applied)
      expect(result).to have_key(:strategy_used)
      expect(result).to have_key(:processing_time)
      expect(result[:rewrite_applied]).to be(true)
      expect(result[:strategy_used]).to eq('rhythm')
    end

    it 'applies different rewriting strategies' do
      strategies = %w[rhythm stress intonation hybrid comprehensive]

      strategies.each do |strategy|
        guidance = mock_rewrite_guidance.dup
        guidance[:overall_strategy][:primary_focus] = strategy

        result = rewriter.rewrite_text(text_analysis, guidance, strategy: strategy)
        expect(result[:strategy_used]).to eq(strategy)
      end
    end

    it 'applies iterative refinement when enabled' do
      options = { iterative_refinement: true, max_iterations: 2 }

      result = rewriter.rewrite_text(text_analysis, mock_rewrite_guidance, options)

      expect(result).to have_key(:total_refinement_iterations)
      expect(result[:total_refinement_iterations]).to be >= 0
    end

    it 'validates meaning preservation' do
      options = { preserve_meaning: true, meaning_threshold: 0.9 }

      # Mock a response that fails meaning preservation
      poor_response = double('LLMResponse', content: 'Completely different text with no relation.')
      allow(mock_llm_client).to receive(:ask).and_return(poor_response)

      result = rewriter.rewrite_text(text_analysis, mock_rewrite_guidance, options)

      # Should fallback to original text
      expect(result[:rewrite_applied]).to be(false)
      expect(result[:fallback_reason]).to eq('meaning_preservation_failed')
    end

    it 'handles LLM timeout gracefully' do
      allow(mock_llm_client).to receive(:ask).and_raise(Timeout::Error.new('Request timed out'))

      expect { rewriter.rewrite_text(text_analysis, mock_rewrite_guidance) }.to raise_error(/timed out/)
    end

    it 'validates input parameters' do
      expect do
        rewriter.rewrite_text(nil, mock_rewrite_guidance)
      end.to raise_error(ArgumentError, /Text analysis must be a hash/)
      expect do
        rewriter.rewrite_text(text_analysis, nil)
      end.to raise_error(ArgumentError, /Rewrite guidance must be a hash/)
      expect do
        rewriter.rewrite_text({}, mock_rewrite_guidance)
      end.to raise_error(ArgumentError, /Text analysis must be a hash/)
    end
  end

  describe '#generate_pattern_informed_prompts' do
    it 'generates appropriate prompts for different strategies' do
      strategies = %w[rhythm stress intonation hybrid comprehensive]

      strategies.each do |strategy|
        prompts = rewriter.generate_pattern_informed_prompts(text_analysis, mock_rewrite_guidance, strategy)

        expect(prompts).to have_key(:system)
        expect(prompts).to have_key(:user)
        expect(prompts).to have_key(:strategy)
        expect(prompts[:strategy]).to eq(strategy)
        expect(prompts[:system]).to include('speech pattern')
        expect(prompts[:user]).to include(sample_text)
      end
    end

    it 'includes strategy-specific guidance in prompts' do
      rhythm_prompts = rewriter.generate_pattern_informed_prompts(text_analysis, mock_rewrite_guidance, 'rhythm')
      expect(rhythm_prompts[:user]).to include('RHYTHM PATTERN TARGETS')
      expect(rhythm_prompts[:user]).to include('120 BPM')

      stress_prompts = rewriter.generate_pattern_informed_prompts(text_analysis, mock_rewrite_guidance, 'stress')
      expect(stress_prompts[:user]).to include('STRESS PATTERN TARGETS')
      expect(stress_prompts[:user]).to include('iambic')
    end

    it 'handles intonation guidance availability' do
      # Test with available intonation
      intonation_prompts = rewriter.generate_pattern_informed_prompts(text_analysis, mock_rewrite_guidance,
                                                                      'intonation')
      expect(intonation_prompts[:user]).to include('INTONATION PATTERN TARGETS')

      # Test with unavailable intonation
      guidance_no_intonation = mock_rewrite_guidance.dup
      guidance_no_intonation[:intonation_guidance][:available] = false

      prompts = rewriter.generate_pattern_informed_prompts(text_analysis, guidance_no_intonation, 'intonation')
      expect(prompts[:strategy]).to eq('intonation')
    end
  end

  describe 'strategy-specific rewriting methods' do
    describe '#rewrite_for_rhythm_patterns' do
      it 'focuses on rhythm optimization' do
        result = rewriter.send(:rewrite_for_rhythm_patterns, text_analysis, mock_rewrite_guidance, {})

        expect(result).to have_key(:rewritten_text)
        expect(result).to have_key(:prompts_used)
        expect(result[:prompts_used][:strategy]).to eq('rhythm')
      end
    end

    describe '#rewrite_for_stress_patterns' do
      it 'focuses on stress optimization' do
        result = rewriter.send(:rewrite_for_stress_patterns, text_analysis, mock_rewrite_guidance, {})

        expect(result).to have_key(:rewritten_text)
        expect(result).to have_key(:prompts_used)
        expect(result[:prompts_used][:strategy]).to eq('stress')
      end
    end

    describe '#rewrite_for_intonation_patterns' do
      it 'focuses on intonation when available' do
        result = rewriter.send(:rewrite_for_intonation_patterns, text_analysis, mock_rewrite_guidance, {})

        expect(result).to have_key(:rewritten_text)
        expect(result).to have_key(:prompts_used)
        expect(result[:prompts_used][:strategy]).to eq('intonation')
      end

      it 'falls back to rhythm when intonation unavailable' do
        guidance_no_intonation = mock_rewrite_guidance.dup
        guidance_no_intonation[:intonation_guidance][:available] = false

        expect(rewriter).to receive(:rewrite_for_rhythm_patterns).and_call_original

        result = rewriter.send(:rewrite_for_intonation_patterns, text_analysis, guidance_no_intonation, {})
        expect(result).to have_key(:rewritten_text)
      end
    end

    describe '#rewrite_with_hybrid_strategy' do
      it 'combines multiple pattern considerations' do
        result = rewriter.send(:rewrite_with_hybrid_strategy, text_analysis, mock_rewrite_guidance, {})

        expect(result).to have_key(:rewritten_text)
        expect(result).to have_key(:prompts_used)
        expect(result[:prompts_used][:strategy]).to eq('hybrid')
      end
    end

    describe '#rewrite_with_comprehensive_strategy' do
      it 'considers all available patterns' do
        result = rewriter.send(:rewrite_with_comprehensive_strategy, text_analysis, mock_rewrite_guidance, {})

        expect(result).to have_key(:rewritten_text)
        expect(result).to have_key(:prompts_used)
        expect(result[:prompts_used][:strategy]).to eq('comprehensive')
      end
    end
  end

  describe 'meaning preservation validation' do
    describe '#validate_meaning_preservation' do
      it 'validates similar texts as preserved' do
        original = 'Hello world. This is a test.'
        rewritten = 'Hello there, world. This is a test example.'

        result = rewriter.send(:validate_meaning_preservation, original, rewritten, 0.8)
        expect(result).to be(true)
      end

      it 'rejects significantly different texts' do
        original = 'Hello world. This is a test.'
        rewritten = 'The cat sat on the mat. Fish swim in water.'

        result = rewriter.send(:validate_meaning_preservation, original, rewritten, 0.8)
        expect(result).to be(false)
      end

      it 'handles length ratio validation' do
        original = 'Hello world.'
        rewritten = 'This is a completely different and much longer sentence that bears no resemblance to the original.'

        result = rewriter.send(:validate_meaning_preservation, original, rewritten, 0.8)
        expect(result).to be(false)
      end

      it 'extracts content words correctly' do
        text = 'The quick brown fox jumps over the lazy dog.'
        content_words = rewriter.send(:extract_content_words, text)

        expect(content_words).to include('quick', 'brown', 'fox', 'jumps', 'lazy', 'dog')
        expect(content_words).not_to include('the', 'over')
      end
    end

    describe '#assess_structural_similarity' do
      it 'assesses similar structures as high similarity' do
        text1 = 'Hello world. This is a test.'
        text2 = 'Hello there. This is an example.'

        similarity = rewriter.send(:assess_structural_similarity, text1, text2)
        expect(similarity).to be > 0.8
      end

      it 'assesses different structures as low similarity' do
        text1 = 'Hello.'
        text2 = 'This is a very long sentence with multiple clauses and complex structure.'

        similarity = rewriter.send(:assess_structural_similarity, text1, text2)
        expect(similarity).to be < 0.6
      end
    end
  end

  describe 'iterative refinement' do
    describe '#apply_iterative_refinement' do
      let(:initial_result) do
        {
          rewritten_text: 'Initial rewrite',
          rewritten_analysis: text_analyzer.analyze('Initial rewrite'),
          prompts_used: { strategy: 'rhythm' }
        }
      end

      it 'applies refinement when needed' do
        allow(rewriter).to receive(:assess_refinement_needs).and_return(['rhythm_refinement'])
        allow(rewriter).to receive(:assess_improvement).and_return(true)

        result = rewriter.send(:apply_iterative_refinement, initial_result, mock_rewrite_guidance,
                               { max_iterations: 2 })

        expect(result).to have_key(:total_refinement_iterations)
        expect(result[:total_refinement_iterations]).to be > 0
      end

      it 'stops when no refinement needed' do
        allow(rewriter).to receive(:assess_refinement_needs).and_return([])

        result = rewriter.send(:apply_iterative_refinement, initial_result, mock_rewrite_guidance,
                               { max_iterations: 3 })

        expect(result[:total_refinement_iterations]).to eq(0)
      end

      it 'respects maximum iterations' do
        allow(rewriter).to receive(:assess_refinement_needs).and_return(['rhythm_refinement'])
        allow(rewriter).to receive(:assess_improvement).and_return(true)

        result = rewriter.send(:apply_iterative_refinement, initial_result, mock_rewrite_guidance,
                               { max_iterations: 1 })

        expect(result[:total_refinement_iterations]).to eq(1)
      end
    end

    describe '#assess_refinement_needs' do
      let(:result_with_analysis) do
        {
          rewritten_analysis: {
            sentences: [
              { word_count: 15 },
              { word_count: 3 },
              { word_count: 20 }
            ]
          }
        }
      end

      it 'identifies uneven sentence distribution' do
        needs = rewriter.send(:assess_refinement_needs, result_with_analysis, mock_rewrite_guidance)
        expect(needs).to include('sentence_balance')
      end

      it 'identifies rhythm refinement needs' do
        allow(rewriter).to receive(:rhythm_optimized?).and_return(false)

        needs = rewriter.send(:assess_refinement_needs, result_with_analysis, mock_rewrite_guidance)
        expect(needs).to include('rhythm_refinement')
      end
    end
  end

  describe 'response processing' do
    describe '#extract_rewritten_text' do
      it 'extracts content from string response' do
        response = 'This is the rewritten text.'
        result = rewriter.send(:extract_rewritten_text, response)
        expect(result).to eq('This is the rewritten text.')
      end

      it 'extracts content from RubyLLM::Message response' do
        response = double('RubyLLM::Message', content: 'This is the rewritten text.')
        result = rewriter.send(:extract_rewritten_text, response)
        expect(result).to eq('This is the rewritten text.')
      end

      it 'cleans markdown formatting' do
        response = "```text\nThis is the rewritten text.\n```"
        result = rewriter.send(:extract_rewritten_text, response)
        expect(result).to eq('This is the rewritten text.')
      end

      it 'handles empty responses' do
        expect { rewriter.send(:extract_rewritten_text, '') }.to raise_error(/No content found/)
        expect { rewriter.send(:extract_rewritten_text, nil) }.to raise_error(/No content found/)
      end
    end
  end

  describe 'analysis and assessment methods' do
    describe '#analyze_changes' do
      it 'analyzes changes between original and rewritten text' do
        original = 'Hello world.'
        rewritten = 'Hello there, beautiful world. This is expanded.'

        changes = rewriter.send(:analyze_changes, original, rewritten)

        expect(changes).to have_key(:length_change)
        expect(changes).to have_key(:word_count_change)
        expect(changes).to have_key(:sentence_count_change)
        expect(changes).to have_key(:structural_changes)
        expect(changes[:length_change]).to be > 0
        expect(changes[:word_count_change]).to be > 0
      end
    end

    describe '#identify_structural_changes' do
      it 'identifies sentence splitting' do
        original = 'This is a long sentence with multiple clauses.'
        rewritten = 'This is a long sentence. It has multiple clauses.'

        changes = rewriter.send(:identify_structural_changes, original, rewritten)
        expect(changes).to include('sentence_splitting')
      end

      it 'identifies sentence combining' do
        original = 'This is short. This is also short.'
        rewritten = 'This is short and this is also short.'

        changes = rewriter.send(:identify_structural_changes, original, rewritten)
        expect(changes).to include('sentence_combining')
      end

      it 'identifies word substitution' do
        original = 'The quick brown fox.'
        rewritten = 'The fast brown fox.'

        changes = rewriter.send(:identify_structural_changes, original, rewritten)
        expect(changes).to include('word_substitution')
      end

      it 'identifies word count adjustment' do
        original = 'Hello world.'
        rewritten = 'Hello beautiful world today.'

        changes = rewriter.send(:identify_structural_changes, original, rewritten)
        expect(changes).to include('word_count_adjustment')
      end
    end
  end

  describe 'error handling' do
    it 'handles LLM conversion failures' do
      allow(mock_llm_client).to receive(:ask).and_raise(StandardError.new('LLM error'))

      expect do
        rewriter.rewrite_text(text_analysis, mock_rewrite_guidance)
      end.to raise_error(/LLM rewrite execution failed/)
    end

    it 'creates fallback result for meaning preservation failures' do
      result = rewriter.send(:create_fallback_result, text_analysis, mock_rewrite_guidance)

      expect(result[:rewrite_applied]).to be(false)
      expect(result[:fallback_reason]).to eq('meaning_preservation_failed')
      expect(result[:rewritten_text]).to eq(sample_text)
    end

    it 'handles timeout errors appropriately' do
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error.new('Timeout'))

      expect { rewriter.rewrite_text(text_analysis, mock_rewrite_guidance) }.to raise_error(/timed out/)
    end
  end

  describe 'configuration and options' do
    it 'uses configured options correctly' do
      custom_options = {
        rewrite_strategy: 'stress',
        preserve_meaning: false,
        meaning_threshold: 0.9,
        max_iterations: 5
      }

      custom_rewriter = described_class.new(provider: provider, model: model, **custom_options)
      expect(custom_rewriter.options[:rewrite_strategy]).to eq('stress')
      expect(custom_rewriter.options[:preserve_meaning]).to be(false)
      expect(custom_rewriter.options[:meaning_threshold]).to eq(0.9)
      expect(custom_rewriter.options[:max_iterations]).to eq(5)
    end

    it 'merges default and custom options correctly' do
      custom_rewriter = described_class.new(provider: provider, model: model, preserve_meaning: false)

      # Should have custom value
      expect(custom_rewriter.options[:preserve_meaning]).to be(false)
      # Should have default values for unspecified options
      expect(custom_rewriter.options[:meaning_threshold]).to eq(0.85)
      expect(custom_rewriter.options[:iterative_refinement]).to be(true)
    end
  end
end
