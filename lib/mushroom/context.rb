# frozen_string_literal: true

module Mushroom
  # Mutable campaign state threaded through all phases.  The only place where
  # mutable shared state is permitted.
  class Context
    attr_accessor :target, :account_id, :region, :credentials, :campaign_id,
                  :discovered_buckets, :discovered_principals

    def initialize(target:, region: 'us-east-1')
      @target               = target
      @region               = region
      @account_id           = nil
      @credentials          = nil
      @campaign_id          = "mushroom-#{SecureRandom.hex(4)}"
      @discovered_buckets   = []
      @discovered_principals = []
    end
  end
end
