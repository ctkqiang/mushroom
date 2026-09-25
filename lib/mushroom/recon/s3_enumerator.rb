# frozen_string_literal: true

module Mushroom
  module Recon
    # Probes a list of candidate bucket names anonymously to discover publicly
    # accessible S3 buckets belonging to the target.
    class S3Enumerator
      include AwsClients

      WORDLIST = File.expand_path('../../../config/wordlists/buckets.txt', __dir__)

      def initialize(context:, config:, logger:)
        @context = context
        @config  = config
        @logger  = logger
      end

      # @return [Array<String>] bucket names that responded to an anonymous HEAD
      def enumerate(target:)
        candidates = wordlist_names(target)
        found      = []

        candidates.each do |name|
          next if config.dry_run?

          begin
            s3_anon_client.head_bucket(bucket: name)
            logger.info('s3_enum: bucket exists', bucket: name)
            found << name
          rescue Aws::S3::Errors::NoSuchBucket, Aws::S3::Errors::NotFound
            # expected
          rescue Aws::S3::Errors::AccessDenied
            # bucket exists but is private — still a signal
            logger.debug('s3_enum: bucket private', bucket: name)
            found << name
          rescue StandardError => e
            logger.debug('s3_enum: skip', bucket: name, error: e.message)
          end
        end

        logger.info('s3_enum: complete', found: found.length, dry_run: config.dry_run?)
        found
      end

      private

      attr_reader :context, :config, :logger

      def wordlist_names(target)
        base = File.exist?(WORDLIST) ? File.readlines(WORDLIST, chomp: true) : []
        base.map { |w| "#{target}-#{w}" } + [target.to_s, "#{target}-data", "#{target}-backups"]
      end
    end
  end
end
