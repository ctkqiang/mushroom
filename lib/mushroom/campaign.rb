# frozen_string_literal: true

require 'securerandom'

module Mushroom
  # Orchestrates the full four-phase kill chain and exposes the verdict
  # collection as an Enumerable.
  #
  # Usage (dry-run, safe):
  #   config   = Config.load
  #   logger   = Logger.new(path: config[:audit_path])
  #   campaign = Campaign.new(target: "acme-corp", config: config, logger: logger)
  #   campaign.run
  #   campaign.report
  class Campaign
    include Enumerable

    attr_reader :context, :verdict_store

    def initialize(target:, config:, logger:)
      @config        = config
      @logger        = logger
      @context       = Context.new(target: target)
      @verdict_store = VerdictStore.new(path: config[:verdict_path])
    end

    # Run all four phases in order.
    # Raises PhaseAborted if a phase encounters a fatal error.
    def run
      phase_classes.each do |klass|
        phase = klass.new(
          context: context,
          config: @config,
          logger: @logger,
          verdict_store: verdict_store
        )
        phase.call
      end
    end

    # Implement Enumerable — delegates to verdict_store.
    def each(&)
      verdict_store.each(&)
    end

    # Build a summary report hash.
    #
    # @return [Hash]
    def report
      all       = verdict_store.to_a
      bypassed  = all.count(&:bypass?)
      detected  = all.count(&:original_rule_would_fire)
      {
        campaign_id: context.campaign_id,
        target: context.target,
        summary: {
          total: all.length,
          bypassed: bypassed,
          detected: detected
        },
        verdicts: all.map(&:to_h)
      }
    end

    def close
      verdict_store.close
    end

    private

    def phase_classes
      [
        Phases::Recon,
        Phases::Harvest,
        Phases::Discovery,
        Phases::Exploit
      ]
    end
  end
end
