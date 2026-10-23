# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mushroom::VerdictStore do
  def build_verdict(scenario: 'test_scenario', fire: false)
    Mushroom::Verdict.of(
      scenario: scenario,
      outcome: :simulated,
      original_rule_would_fire: fire,
      reason: 'test'
    )
  end

  it 'appends verdicts and flushes to JSONL immediately' do
    Dir.mktmpdir do |dir|
      path  = File.join(dir, 'verdicts.jsonl')
      store = described_class.new(path: path)
      v     = build_verdict
      store << v
      store.close

      lines = File.readlines(path)
      expect(lines.length).to eq(1)
      parsed = JSON.parse(lines.first)
      expect(parsed['scenario']).to eq('test_scenario')
      expect(parsed['original_rule_would_fire']).to be(false)
    end
  end

  it 'is Enumerable and iterates in insertion order' do
    store = described_class.new(path: File::NULL)
    v1 = build_verdict(scenario: 'first')
    v2 = build_verdict(scenario: 'second')
    store << v1 << v2
    scenarios = store.map(&:scenario)
    expect(scenarios).to eq(%w[first second])
    store.close
  end

  it 'returns self from << enabling chaining' do
    store = described_class.new(path: File::NULL)
    result = (store << build_verdict)
    expect(result).to be(store)
    store.close
  end

  it 'counts records via Enumerable#count' do
    store = described_class.new(path: File::NULL)
    3.times { store << build_verdict }
    expect(store.count).to eq(3)
    store.close
  end

  it 'does not raise on double close' do
    store = described_class.new(path: File::NULL)
    store.close
    expect { store.close }.not_to raise_error
  end

  it 'creates parent directories automatically' do
    Dir.mktmpdir do |dir|
      nested = File.join(dir, 'deep', 'sub', 'verdicts.jsonl')
      store  = described_class.new(path: nested)
      store << build_verdict
      store.close
      expect(File.exist?(nested)).to be(true)
    end
  end
end
