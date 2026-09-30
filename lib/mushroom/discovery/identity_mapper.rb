# frozen_string_literal: true

module Mushroom
  module Discovery
    # Calls sts:GetCallerIdentity to establish who we are in the target account.
    class IdentityMapper
      include AwsClients

      def initialize(context:, config:, logger:)
        @context = context
        @config  = config
        @logger  = logger
      end

      # Populate context.account_id and return the caller ARN.
      #
      # @return [String] caller ARN, or a mock ARN in dry_run mode
      def whoami
        if config.dry_run?
          mock_arn = 'arn:aws:sts::000000000000:assumed-role/DryRunRole/session'
          context.account_id = '000000000000'
          logger.info('identity_mapper: dry_run identity', arn: mock_arn)
          return mock_arn
        end

        resp = sts_client.get_caller_identity
        context.account_id = resp.account
        logger.info('identity_mapper: caller identity',
                    account: resp.account, arn: resp.arn, user_id: resp.user_id)
        resp.arn
      end

      private

      attr_reader :context, :config, :logger
    end
  end
end
