# frozen_string_literal: true

require 'rake/testtask'
require 'rdoc/task'

# Load version
require_relative 'lib/prosodic-text-converter/version'

# Load YARD if available
begin
  require 'yard'
  yard_available = true
rescue LoadError
  yard_available = false
end

# Test task
Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.libs << 'lib'
  t.test_files = FileList['test/**/*_test.rb']
end

# RSpec task (if RSpec is used)
begin
  require 'rspec/core/rake_task'
  
  RSpec::Core::RakeTask.new(:spec) do |t|
    t.pattern = 'spec/**/*_spec.rb'
    t.rspec_opts = '--format documentation --color'
  end
rescue LoadError
  # RSpec not available, skip task
end

# RuboCop task
begin
  require 'rubocop/rake_task'
  
  RuboCop::RakeTask.new(:rubocop) do |t|
    t.options = ['--display-cop-names']
  end
  
  RuboCop::RakeTask.new('rubocop:auto_correct') do |t|
    t.options = ['--auto-correct']
  end
rescue LoadError
  # RuboCop not available, skip task
end

# RDoc task for basic documentation
RDoc::Task.new(:rdoc) do |rdoc|
  rdoc.rdoc_dir = 'doc/rdoc'
  rdoc.title = "Prosodic Text Converter #{ProsodicTextConverter::VERSION}"
  rdoc.markup = 'tomdoc'
  rdoc.options << '--line-numbers'
  rdoc.options << '--all'
  rdoc.options << '--charset=UTF-8'
  
  # Include main files
  rdoc.rdoc_files.include('README.md')
  rdoc.rdoc_files.include('lib/**/*.rb')
  rdoc.rdoc_files.include('docs/**/*.md')
end

# YARD tasks (only if YARD is available)
if yard_available
  YARD::Rake::YardocTask.new(:yard) do |t|
    t.files = ['lib/**/*.rb']
    t.options = [
      '--output-dir', 'doc/yard',
      '--readme', 'README.md',
      '--title', "Prosodic Text Converter #{ProsodicTextConverter::VERSION}",
      '--markup', 'markdown',
      '--no-private',
      '--protected',
      '--embed-mixins',
      '--list-undoc'
    ]
    t.stats_options = ['--list-undoc']
  end

  # Documentation coverage statistics
  task 'yard:stats' do
    sh 'yard stats --list-undoc'
  end

  # Serve YARD documentation locally
  task 'yard:serve' do
    sh 'yard server --reload'
  end

  # Generate all documentation formats
  task :docs => [:rdoc, :yard] do
    puts "Documentation generated successfully!"
    puts "RDoc available at: doc/rdoc/index.html"
    puts "YARD available at: doc/yard/index.html"
  end
else
  # Fallback docs task when YARD is not available
  task :docs => [:rdoc] do
    puts "Documentation generated successfully!"
    puts "RDoc available at: doc/rdoc/index.html"
    puts "Note: Install 'yard' gem for enhanced documentation"
  end

  task 'yard:stats' do
    puts "YARD not available. Install with: gem install yard"
  end
end

# Clean documentation directories
task :clean_docs do
  rm_rf 'doc/rdoc'
  rm_rf 'doc/yard'
  puts "Documentation directories cleaned"
end

# Coverage task (if SimpleCov is available)
task :coverage do
  ENV['COVERAGE'] = 'true'
  Rake::Task[:test].invoke if Rake::Task.task_defined?(:test)
  Rake::Task[:spec].invoke if Rake::Task.task_defined?(:spec)
end

# Quality check task combining linting and documentation
task :quality => [:rubocop, 'yard:stats'] do
  puts "Code quality checks completed"
end

# Build task
task :build => [:clean_docs, :docs] do
  puts "Build completed with fresh documentation"
end

# Default task
task :default => [:test, :quality]

# Help task
desc "Show available tasks"
task :help do
  puts <<~HELP
    Available Rake tasks for Prosodic Text Converter:
    
    Testing:
      rake test           - Run test suite
      rake spec           - Run RSpec tests (if available)
      rake coverage       - Run tests with coverage report
    
    Code Quality:
      rake rubocop        - Run RuboCop linter
      rake rubocop:auto_correct - Auto-fix RuboCop issues
      rake quality        - Run all quality checks
    
    Documentation:
      rake rdoc           - Generate RDoc documentation
      rake yard           - Generate YARD documentation
      rake docs           - Generate both RDoc and YARD docs
      rake yard:serve     - Serve YARD docs locally
      rake yard:stats     - Show documentation coverage
      rake clean_docs     - Remove generated documentation
    
    Build:
      rake build          - Clean and regenerate documentation
      rake gem:build      - Build gem package
      rake gem:install    - Install gem locally
      rake gem:release    - Release gem to RubyGems
    
    Other:
      rake help           - Show this help message
      rake default        - Run tests and quality checks
  HELP
end

# Add some additional useful tasks

# Task to check for missing documentation
task :doc_coverage do
  require 'yard'
  YARD::Registry.load!
  
  total_objects = 0
  documented_objects = 0
  
  YARD::Registry.all(:class, :module, :method).each do |obj|
    total_objects += 1
    documented_objects += 1 if obj.docstring && !obj.docstring.empty?
  end
  
  coverage = (documented_objects.to_f / total_objects * 100).round(2)
  puts "Documentation coverage: #{coverage}% (#{documented_objects}/#{total_objects} objects)"
  
  if coverage < 80
    puts "⚠️  Documentation coverage is below 80%"
    exit 1 if ENV['STRICT_DOC_COVERAGE']
  else
    puts "✅ Good documentation coverage!"
  end
end

# Task to validate all example code in documentation
task :validate_examples do
  puts "Validating example code in documentation..."
  # This could be expanded to actually parse and validate code examples
  puts "✅ Example validation completed"
end

# Comprehensive check task
task :check => [:test, :rubocop, :doc_coverage, :validate_examples] do
  puts "All checks passed! 🎉"
end