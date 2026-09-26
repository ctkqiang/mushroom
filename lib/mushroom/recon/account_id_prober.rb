# frozen_string_literal: true

module Mushroom
  module Recon
    # Derives the target AWS account ID via unauthenticated S3 techniques.
    # In dry_run mode the prober returns a placeholder without network I/O.
    class AccountIdProber
      def initialize(context:, config:, logger:)
        @context = context
        @config  = config
        @logger  = logger
      end

      # Attempt to discover the account ID.
      # Returns nil when nothing can be determined without live AWS access.
      #
      # @return [String, nil]
      def probe(buckets:)
        if config.dry_run?
          logger.info('account_id_prober: dry_run — skipping network probe')
          return nil
        end

        buckets.each do |bucket|
          id = extract_from_bucket_policy(bucket)
          return id if id
        end

        nil
      end

      private

      attr_reader :context, :config, :logger

      def extract_from_bucket_policy(bucket)
        # The canonical anonymous technique: an S3 bucket-policy error message
        # often embeds the account ID.  We treat this as best-effort.
        client = Aws::S3::Client.new(region: 'us-east-1', anonymous: true)
        client.get_bucket_policy(bucket: bucket)
        nil
      rescue Aws::S3::Errors::AccessDenied => e
        # Error message may contain "arn:aws:iam::ACCOUNT_ID:"
        m = e.message.match(/arn:aws:iam::(\d{12}):/)
        id = m&.[](1)
        logger.info('account_id_prober: found via error', account_id: id) if id
        id
      rescue StandardError
        nil
      end
    end
  end
end
