# frozen_string_literal: true

require 'bundler/setup'
require 'rspec'

# Load the main library
require_relative '../lib/prosodic-text-converter'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on Module and main
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Configure test output
  config.formatter = :documentation
  config.color = true
end
