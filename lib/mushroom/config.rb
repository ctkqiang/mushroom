# frozen_string_literal: true

require 'yaml'

module Mushroom
  # Frozen configuration object.  Build via Config.load; never mutate after
  # construction.  All keys are symbols.
  class Config
    DEFAULTS = {
      dry_run: true,
      cleanup: true,
      allow_accounts: [],
      deny_accounts: [],
      timeframe_hours: 1,
      tag_prefix: 'Simulation',
      verdict_path: 'tmp/mushroom-verdicts.jsonl',
      audit_path: 'tmp/mushroom-audit.jsonl',
      ssrf_endpoint: nil,
      template_bucket: nil,
      execution_role_arn: nil,
      profile: nil
    }.freeze

    # Build a Config from optional YAML file path + runtime overrides.
    # Overrides win over YAML, which wins over DEFAULTS.
    #
    # @param path     [String, nil] path to settings YAML
    # @param overrides [Hash]       keyword overrides (symbol keys)
    # @return [Config]
    def self.load(path: nil, overrides: {})
      file_cfg = path ? load_yaml(path) : {}
      merged   = DEFAULTS.merge(file_cfg).merge(overrides.transform_keys(&:to_sym))
      new(merged)
    end

    def initialize(attrs)
      @data = attrs.freeze
    end

    # Delegate [] to underlying hash (symbol keys).
    def [](key) = @data.fetch(key)

    # True when dry_run is enabled (the default).
    def dry_run? = @data[:dry_run]

    # True when automatic cleanup is enabled (the default).
    def cleanup? = @data[:cleanup]

    # Raise ConfigError if +account_id+ is in the deny list or not in an
    # explicit allow list (when one is configured).
    def assert_safe!(account_id:)
      deny = Array(@data[:deny_accounts])
      allow = Array(@data[:allow_accounts])

      raise ConfigError, "Account #{account_id} is in the deny list" if deny.include?(account_id)

      return unless allow.any? && !allow.include?(account_id)

      raise ConfigError,
            "Account #{account_id} is not in the allow list (#{allow.join(', ')})"
    end

    def to_h = @data.dup

    def self.load_yaml(path)
      raw = YAML.safe_load_file(path, symbolize_names: true) || {}
      raw.is_a?(Hash) ? raw : {}
    rescue Errno::ENOENT
      {}
    end
  end
end
