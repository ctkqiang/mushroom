# frozen_string_literal: true

module Mushroom
  module Recon
    # Brute-forces role/user names against the target account to enumerate
    # valid IAM principals (unauthenticated STS error-oracle technique).
    class PrincipalBruteforcer
      WORDLIST_ROLES  = File.expand_path('../../../config/wordlists/roles.txt', __dir__)
      WORDLIST_USERS  = File.expand_path('../../../config/wordlists/users.txt', __dir__)

      def initialize(context:, config:, logger:)
        @context = context
        @config  = config
        @logger  = logger
      end

      # @param account_id [String]
      # @return [Array<String>] valid ARNs discovered
      def bruteforce(account_id:)
        return [] if config.dry_run?
        return [] unless account_id

        candidates = build_candidates(account_id)
        valid      = []

        candidates.each do |arn|
          next unless valid_principal?(arn)

          valid << arn
          logger.info('principal_bruteforcer: found', arn: arn)
        end

        valid
      end

      private

      attr_reader :context, :config, :logger

      def build_candidates(account_id)
        roles = File.exist?(WORDLIST_ROLES) ? File.readlines(WORDLIST_ROLES, chomp: true) : []
        users = File.exist?(WORDLIST_USERS) ? File.readlines(WORDLIST_USERS, chomp: true) : []

        roles.map { |r| "arn:aws:iam::#{account_id}:role/#{r}" } +
          users.map { |u| "arn:aws:iam::#{account_id}:user/#{u}" }
      end

      def valid_principal?(arn)
        # STS oracle: AssumeRole with an invalid external-id returns a
        # specific error for *existing* principals vs. a different one for
        # non-existent principals.
        client = Aws::STS::Client.new(region: 'us-east-1')
        client.assume_role(
          role_arn: arn,
          role_session_name: 'mushroom-probe',
          external_id: 'INVALID_EXTERNAL_ID_PROBE'
        )
        false # Succeeded unexpectedly — treat as valid
      rescue Aws::STS::Errors::AccessDenied
        true   # Principal exists but access was denied — valid!
      rescue Aws::STS::Errors::InvalidClientTokenId, Aws::STS::Errors::NoSuchEntity,
             StandardError
        false  # Principal does not exist or unhandled error
      end
    end
  end
end
