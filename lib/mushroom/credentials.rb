# frozen_string_literal: true

require 'time'

module Mushroom
  # Immutable value object representing temporary AWS credentials harvested from
  # IMDS or STS.  Never log or print #access_key_id directly; use #redacted.
  Credentials = Data.define(:access_key_id, :secret_access_key, :session_token,
                            :expiration, :source_arn) do
    # Build from a raw IMDS JSON hash (keys are PascalCase strings).
    #
    # @param raw        [Hash]   IMDS response body (already parsed)
    # @param source_arn [String] ARN of the role the credentials belong to
    # @return [Credentials]
    def self.from_imds(raw, source_arn:)
      new(
        access_key_id: raw.fetch('AccessKeyId'),
        secret_access_key: raw.fetch('SecretAccessKey'),
        session_token: raw.fetch('Token'),
        expiration: Time.iso8601(raw.fetch('Expiration')),
        source_arn: source_arn
      )
    end

    # Build from an STS AssumeRole response.
    #
    # @param resp       [Aws::STS::Types::AssumeRoleResponse]
    # @param source_arn [String]
    # @return [Credentials]
    def self.from_sts(resp, source_arn:)
      creds = resp.credentials
      new(
        access_key_id: creds.access_key_id,
        secret_access_key: creds.secret_access_key,
        session_token: creds.session_token,
        expiration: creds.expiration,
        source_arn: source_arn
      )
    end

    # Convert to an Aws::Credentials instance suitable for SDK clients.
    #
    # @return [Aws::Credentials]
    def to_aws
      Aws::Credentials.new(access_key_id, secret_access_key, session_token)
    end

    # @return [Boolean] true when the credentials have passed their expiry time
    def expired?
      expiration < Time.now.utc
    end

    # Return a display-safe string that masks the bulk of the access key.
    # Only the first four characters (e.g. "ASIA") are preserved.
    #
    # @return [String]
    def redacted
      prefix = access_key_id.length > 4 ? access_key_id[0, 4] : access_key_id
      "#{prefix}#{'*' * [access_key_id.length - 4, 8].max} (#{source_arn})"
    end
  end
end
