# frozen_string_literal: true

require 'json'
require 'colorize'
require 'fileutils'

module Mushroom
  # Dual-sink logger: human-readable coloured STDOUT + append-only JSONL file.
  class Logger
    LEVELS = %i[debug info warn error].freeze

    def initialize(path:, io: $stdout, level: :info)
      FileUtils.mkdir_p(File.dirname(path)) if path != File::NULL
      @file  = File.open(path, 'a')
      @io    = io
      @level = LEVELS.index(level) || 1
    end

    LEVELS.each_with_index do |lvl, idx|
      define_method(lvl) do |message, **fields|
        log(lvl, idx, message, fields)
      end
    end

    def close
      @file.close unless @file.closed?
    end

    private

    def log(level, idx, message, fields)
      return if idx < @level

      entry = { at: Time.now.utc.iso8601, level: level, message: message }.merge(fields)
      @file.puts(JSON.generate(entry))
      @file.flush

      colour = { debug: :light_black, info: :cyan, warn: :yellow, error: :red }.fetch(level, :white)
      prefix = "[#{level.to_s.upcase}]".colorize(colour)
      @io.puts("#{prefix} #{message}")
    end
  end
end
