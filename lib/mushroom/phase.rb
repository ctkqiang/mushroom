# frozen_string_literal: true

module Mushroom
  # Abstract base class for all campaign phases.
  #
  # Template method pattern:
  #   1. #preflight! – guards (account allow/deny, dry_run reminders)
  #   2. #execute    – subclass-defined phase logic
  #   3. #run_cleanups – registered blocks executed in LIFO order via ensure
  #
  # Subclasses must implement #execute.
  # Every AWS-mutating step in #execute should call with_cleanup { ... }
  # immediately after the creation call so the resource is always cleaned up.
  class Phase
    include AwsClients

    def initialize(context:, config:, logger:, verdict_store:)
      @context       = context
      @config        = config
      @logger        = logger
      @verdict_store = verdict_store
      @cleanups      = []
    end

    # Public entry point.  Calls preflight!, execute, then run_cleanups.
    def call
      preflight!
      execute
    ensure
      run_cleanups
    end

    protected

    attr_reader :context, :config, :logger, :verdict_store

    # Subclasses override this to perform phase work.
    def execute
      raise NotImplementedError, "#{self.class}#execute is not implemented"
    end

    # Default preflight: asserts account safety when account_id is known.
    def preflight!
      return unless context.account_id

      config.assert_safe!(account_id: context.account_id)
    end

    # Register a cleanup block executed in reverse order in the ensure clause.
    # The block is called even when #execute raises.
    def with_cleanup(&block)
      @cleanups << block
    end

    # Record a Verdict and write it to the store.
    def verdict(**)
      v = Verdict.of(**)
      verdict_store << v
      logger.info('verdict', scenario: v.scenario, fire: v.original_rule_would_fire,
                             outcome: v.outcome.to_s)
      v
    end

    private

    def run_cleanups
      return unless config.cleanup?

      @cleanups.reverse_each do |blk|
        blk.call
      rescue StandardError => e
        logger.warn('cleanup failed', error: e.message)
      end
      @cleanups.clear
    end
  end
end
