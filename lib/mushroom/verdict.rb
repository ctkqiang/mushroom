# frozen_string_literal: true

require 'time'

module Mushroom
  # Immutable value object representing the detection outcome for one exploit
  # scenario.  Written to tmp/mushroom-verdicts.jsonl by VerdictStore.
  #
  # Fields
  #   scenario                - unique scenario identifier string
  #   outcome                 - Symbol: :simulated | :skipped | :error
  #   original_rule_would_fire - Boolean; false means a detection gap exists
  #   reason                  - human-readable explanation
  #   at                      - Time of recording (UTC)
  Verdict = Data.define(:scenario, :outcome, :original_rule_would_fire, :reason, :at) do
    # Factory: stamps the current UTC time automatically.
    #
    # @param scenario                [String]
    # @param outcome                 [Symbol]
    # @param original_rule_would_fire [Boolean]
    # @param reason                  [String]
    # @return [Verdict]
    def self.of(scenario:, outcome:, original_rule_would_fire:, reason:)
      new(
        scenario: scenario,
        outcome: outcome,
        original_rule_would_fire: original_rule_would_fire,
        reason: reason,
        at: Time.now.utc
      )
    end

    # @return [Boolean] true when the KQL rule would NOT catch this technique
    def bypass?
      !original_rule_would_fire
    end

    # Serialize to a plain Hash suitable for JSON encoding.
    # +at+ is rendered as an ISO 8601 string.
    #
    # @return [Hash]
    def to_h
      super.merge(at: at.iso8601(6), outcome: outcome.to_s)
    end
  end
end
