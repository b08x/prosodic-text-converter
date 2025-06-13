#!/usr/bin/env ruby
# frozen_string_literal: true

# The Logging module provides a centralized way to handle logging
# across the application. It allows for configuring loggers with
# specific settings like log directory, level, max size, and max files.
#
# It can be included in any class to provide a `logger` instance method
# that is automatically configured with the class and method name.
module Logging
  module_function

  require 'logger'
  require 'fileutils' # Added for mkdir_p

  # @!visibility private
  # The directory where log files will be stored.
  # Configurable via PROSODIC_LOG_DIR environment variable.
  # Defaults to `log` in the current working directory.
  LOG_DIR = File.expand_path(ENV.fetch('PROSODIC_LOG_DIR', File.join(Dir.pwd, 'log')))

  # @!visibility private
  # The default logging level.
  # Configurable via PROSODIC_LOG_LEVEL environment variable.
  # Defaults to `Logger::INFO`.
  LOG_LEVEL = case ENV.fetch('PROSODIC_LOG_LEVEL', 'INFO').upcase
              when 'DEBUG' then Logger::DEBUG
              when 'INFO' then Logger::INFO
              when 'WARN' then Logger::WARN
              when 'ERROR' then Logger::ERROR
              when 'FATAL' then Logger::FATAL
              else Logger::INFO
              end

  # @!visibility private
  # The maximum size of a single log file in bytes.
  # Configurable via PROSODIC_LOG_MAX_SIZE environment variable.
  # Defaults to 6MB (6 * 1024 * 1024).
  LOG_MAX_SIZE = ENV.fetch('PROSODIC_LOG_MAX_SIZE', '6145728').to_i

  # @!visibility private
  # The maximum number of log files to keep (for rotation).
  # Configurable via PROSODIC_LOG_MAX_FILES environment variable.
  # Defaults to 10.
  LOG_MAX_FILES = ENV.fetch('PROSODIC_LOG_MAX_FILES', '10').to_i

  # @!visibility private
  # A cache for logger instances, keyed by classname.
  # This prevents reconfiguring loggers unnecessarily.
  @loggers = {}

  # Provides a logger instance for the current class and method.
  #
  # The logger's `progname` will be set to "ClassName#methodName"
  # from where this method is called.
  #
  # @example
  #   class MyClass
  #     include Logging
  #
  #     def do_something
  #       logger.info "Doing something"
  #     end
  #   end
  #
  # @return [Logger] The logger instance for the calling context.
  def logger
    # Determines the class name of the object calling this method.
    # If called from a class method, `self` is the class itself.
    # If called from an instance method, `self.class` is the class.
    classname = is_a?(Module) ? name : self.class.name
    # Extracts the method name from the call stack.
    methodname = caller[0][/`([^']*)'/, 1]
    @logger ||= Logging.logger_for(classname, methodname)
    @logger.progname = "#{classname}##{methodname}"
    @logger
  end

  class << self
    # Returns the configured log level for new loggers.
    #
    # @return [Integer] The log level (e.g., `Logger::DEBUG`, `Logger::INFO`).
    def log_level
      LOG_LEVEL
    end

    # Retrieves or creates a logger for a given classname.
    #
    # Loggers are cached by classname to avoid redundant configuration.
    # The `methodname` parameter is currently passed to `configure_logger_for`
    # but not directly used in the default configuration of the log file name.
    #
    # @param classname [String] The name of the class for which to get the logger.
    # @param methodname [String] The name of the method (currently used to pass to `configure_logger_for`).
    # @return [Logger] The configured logger instance.
    def logger_for(classname, methodname)
      @loggers[classname] ||= configure_logger_for(classname, methodname)
    end

    # Configures and returns a new logger instance.
    #
    # The logger is set up to write to a dated log file within LOG_DIR,
    # with rotation based on LOG_MAX_FILES and LOG_MAX_SIZE.
    #
    # @param _classname [String] The class name (currently unused in file naming).
    # @param _methodname [String] The method name (currently unused in file naming).
    # @return [Logger] The newly configured logger instance.
    def configure_logger_for(_classname, _methodname)
      current_date = Time.now.strftime('%Y-%m-%d')
      log_file = File.join(LOG_DIR, "prosodic-text-converter-#{current_date}.log")
      # Ensure the log directory exists
      FileUtils.mkdir_p(LOG_DIR) unless Dir.exist?(LOG_DIR)
      logger = Logger.new(log_file, LOG_MAX_FILES, LOG_MAX_SIZE)
      logger.level = log_level
      logger
    end
  end
end
