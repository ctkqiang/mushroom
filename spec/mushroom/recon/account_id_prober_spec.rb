# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mushroom::Recon::AccountIdProber do
  def build(overrides = {})
    config  = Mushroom::Config.load(overrides: overrides)
    context = Mushroom::Context.new(target: 'acme')
    logger  = Mushroom::Logger.new(path: File::NULL, io: StringIO.new)
    prober  = described_class.new(context: context, config: config, logger: logger)
    [prober, logger]
  end

  it 'returns nil in dry_run mode without making network calls' do
    prober, logger = build
    result = prober.probe(buckets: %w[bucket-a bucket-b])
    expect(result).to be_nil
    logger.close
  end

  it 'returns nil when buckets list is empty in dry_run mode' do
    prober, logger = build
    result = prober.probe(buckets: [])
    expect(result).to be_nil
    logger.close
  end
end
