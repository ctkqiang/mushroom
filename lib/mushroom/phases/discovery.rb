# frozen_string_literal: true

module Mushroom
  module Phases
    # Phase 3 – Discovery
    # Establish caller identity (whoami) and simulate effective permissions.
    class Discovery < Phase
      def execute
        mapper     = Mushroom::Discovery::IdentityMapper.new(
          context: context, config: config, logger: logger
        )
        caller_arn = mapper.whoami

        config.assert_safe!(account_id: context.account_id) if context.account_id

        fuzzer = Mushroom::Discovery::PermissionFuzzer.new(
          context: context, config: config, logger: logger
        )
        results = fuzzer.fuzz(caller_arn: caller_arn)

        logger.info('discovery: phase complete',
                    caller_arn: caller_arn,
                    permissions: results)
      end
    end
  end
end
