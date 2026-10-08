# frozen_string_literal: true

module Mushroom
  module Phases
    # Phase 1 – Recon
    # Unauthenticated discovery: S3 bucket enumeration, account-ID probing,
    # IAM principal brute-forcing.
    class Recon < Phase
      def execute
        enumerator = Mushroom::Recon::S3Enumerator.new(context: context, config: config, logger: logger)
        buckets    = enumerator.enumerate(target: context.target)
        context.discovered_buckets = buckets

        prober     = Mushroom::Recon::AccountIdProber.new(context: context, config: config, logger: logger)
        account_id = prober.probe(buckets: buckets)
        context.account_id = account_id if account_id

        config.assert_safe!(account_id: context.account_id) if context.account_id

        bruteforcer = Mushroom::Recon::PrincipalBruteforcer.new(
          context: context, config: config, logger: logger
        )
        principals = bruteforcer.bruteforce(account_id: context.account_id)
        context.discovered_principals = principals

        logger.info('recon: phase complete',
                    buckets: context.discovered_buckets.length,
                    principals: context.discovered_principals.length)
      end
    end
  end
end
