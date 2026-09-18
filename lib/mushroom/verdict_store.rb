# frozen_string_literal: true

require 'json'
require 'fileutils'

module Mushroom
  # Append-only JSONL sink that also exposes all recorded verdicts as an
  # Enumerable collection.
  class VerdictStore
    include Enumerable

    def initialize(path:)
      FileUtils.mkdir_p(File.dirname(path)) if path != File::NULL
      @path     = path
      @file     = File.open(path, 'a')
      @verdicts = []
    end

    # Append a Verdict and flush immediately.
    #
    # @param verdict [Verdict]
    def <<(verdict)
      @verdicts << verdict
      @file.puts(JSON.generate(verdict.to_h))
      @file.flush
      self
    end

    # Implement Enumerable — iterates over Verdict objects in insertion order.
    def each(&)
      @verdicts.each(&)
    end

    def close
      @file.close unless @file.closed?
    end
  end
end
