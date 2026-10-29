# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mushroom::Discovery::IdentityMapper do
  def build(overrides = {})
    config  = Mushroom::Config.load(overrides: overrides)
    context = Mushroom::Context.new(target: 'test')
    logger  = Mushroom::Logger.new(path: File::NULL, io: StringIO.new)
    mapper  = described_class.new(context: context, config: config, logger: logger)
    [mapper, context, logger]
  end

  it 'returns the mock ARN in dry_run mode' do
    mapper, context, logger = build
    arn = mapper.whoami
    expect(arn).to eq('arn:aws:sts::000000000000:assumed-role/DryRunRole/session')
    expect(context.account_id).to eq('000000000000')
    logger.close
  end

  it 'sets context.account_id in dry_run mode' do
    mapper, context, logger = build
    mapper.whoami
    expect(context.account_id).not_to be_nil
    logger.close
  end
end
