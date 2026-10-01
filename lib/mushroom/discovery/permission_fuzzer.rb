# frozen_string_literal: true

module Mushroom
  module Discovery
    # Simulates an iam:SimulatePrincipalPolicy call to enumerate effective
    # permissions without attempting real mutations.
    class PermissionFuzzer
      include AwsClients

      PROBE_ACTIONS = %w[
        cloudformation:CreateStack
        cloudformation:UpdateStack
        iam:CreateRole
        iam:AttachRolePolicy
        iam:PutRolePolicy
        iam:PassRole
      ].freeze

      def initialize(context:, config:, logger:)
        @context = context
        @config  = config
        @logger  = logger
      end

      # Simulate the given list of actions against the caller principal.
      #
      # @param caller_arn [String]
      # @return [Hash{String => String}] action → "allowed" | "implicitDeny" | "explicitDeny"
      def fuzz(caller_arn:, actions: PROBE_ACTIONS)
        return mock_results(actions) if config.dry_run?

        resp = iam_client.simulate_principal_policy(
          policy_source_arn: caller_arn,
          action_names: actions
        )

        results = resp.evaluation_results.to_h do |r|
          [r.eval_action_name, r.eval_decision]
        end

        logger.info('permission_fuzzer: simulation complete', results: results)
        results
      end

      private

      attr_reader :context, :config, :logger

      def mock_results(actions)
        actions.to_h do |action|
          [action, 'allowed']
        end
      end
    end
  end
end
