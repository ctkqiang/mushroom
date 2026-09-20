# frozen_string_literal: true

module Mushroom
  # Mixin that provides lazy-initialized AWS service clients.
  # Consumers must expose #config and #context.
  #
  # Supports three credential modes, tried in order:
  #   1. credentials injected via context.credentials (e.g., stolen from IMDS)
  #   2. named AWS profile from config[:profile]
  #   3. default SDK credential chain (instance profile / env vars)
  #
  # When config[:dry_run] is true, no real mutations are sent; callers gate
  # mutation calls behind config.dry_run?.
  module AwsClients
    # @return [Aws::CloudFormation::Client]
    def cfn_client
      @cfn_client ||= build_client(Aws::CloudFormation::Client)
    end

    # @return [Aws::IAM::Client]
    def iam_client
      @iam_client ||= build_client(Aws::IAM::Client)
    end

    # @return [Aws::CloudControlApi::Client]
    def cc_client
      @cc_client ||= build_client(Aws::CloudControlApi::Client)
    end

    # @return [Aws::STS::Client]
    def sts_client
      @sts_client ||= build_client(Aws::STS::Client)
    end

    # @return [Aws::S3::Client]  anonymous client (no credentials)
    def s3_anon_client
      @s3_anon_client ||= Aws::S3::Client.new(
        region: context.region,
        anonymous: true
      )
    end

    private

    def build_client(klass)
      opts = { region: context.region }

      if context.credentials
        opts[:credentials] = context.credentials.to_aws
      elsif config[:profile]
        opts[:profile] = config[:profile]
      end

      klass.new(**opts)
    end
  end
end
