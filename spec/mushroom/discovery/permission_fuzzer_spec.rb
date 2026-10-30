# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mushroom::Discovery::PermissionFuzzer do
  def build(overrides = {})
    config  = Mushroom::Config.load(overrides: overrides)
    context = Mushroom::Context.new(target: 'test')
    logger  = Mushroom::Logger.new(path: File::NULL, io: StringIO.new)
    fuzzer  = described_class.new(context: context, config: config, logger: logger)
    [fuzzer, logger]
  end

  it 'returns allowed for all probe actions in dry_run mode' do
    fuzzer, logger = build
    results = fuzzer.fuzz(caller_arn: 'arn:aws:sts::000:assumed-role/R/s')
    expect(results).to be_a(Hash)
    expect(results.values.uniq).to eq(['allowed'])
    logger.close
  end

  it 'covers all PROBE_ACTIONS in dry_run mode' do
    fuzzer, logger = build
    results = fuzzer.fuzz(caller_arn: 'arn:aws:sts::000:assumed-role/R/s')
    expect(results.keys).to match_array(described_class::PROBE_ACTIONS)
    logger.close
  end

  it 'accepts a custom actions list' do
    fuzzer, logger = build
    results = fuzzer.fuzz(
      caller_arn: 'arn:aws:sts::000:assumed-role/R/s',
      actions: %w[iam:CreateRole s3:GetObject]
    )
    expect(results.keys).to match_array(%w[iam:CreateRole s3:GetObject])
    logger.close
  end
end
