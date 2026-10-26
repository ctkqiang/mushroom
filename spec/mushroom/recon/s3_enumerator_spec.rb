# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mushroom::Recon::S3Enumerator do
  def build(overrides = {})
    config  = Mushroom::Config.load(overrides: overrides)
    context = Mushroom::Context.new(target: 'acme')
    logger  = Mushroom::Logger.new(path: File::NULL, io: StringIO.new)
    enumerator = described_class.new(context: context, config: config, logger: logger)
    [enumerator, logger]
  end

  it 'returns an empty array in dry_run mode (no network calls)' do
    enumerator, logger = build
    result = enumerator.enumerate(target: 'acme')
    expect(result).to eq([])
    logger.close
  end

  it 'generates candidate names from the wordlist and target prefix' do
    enumerator, logger = build
    # Access private method via send for white-box coverage
    names = enumerator.send(:wordlist_names, 'mytarget')
    expect(names).to all(be_a(String))
    expect(names).to include('mytarget')
    expect(names.any? { |n| n.start_with?('mytarget-') }).to be(true)
    logger.close
  end

  it 'wordlist candidates include the raw target and suffixed variants' do
    enumerator, logger = build
    names = enumerator.send(:wordlist_names, 'corp')
    expect(names).to include('corp', 'corp-data', 'corp-backups')
    logger.close
  end
end
