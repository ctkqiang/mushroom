# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mushroom::Verdict do
  it 'serializes a bypass with an ISO8601 timestamp' do
    verdict = described_class.of(
      scenario: 'cloud_control_api',
      outcome: :simulated,
      original_rule_would_fire: false,
      reason: 'Cloud Control is outside the EventSource filter'
    )

    expect(verdict.bypass?).to be(true)
    expect(Time.iso8601(verdict.to_h.fetch(:at))).to eq(verdict.at)
    expect(verdict.to_h.fetch(:scenario)).to eq('cloud_control_api')
  end
end
