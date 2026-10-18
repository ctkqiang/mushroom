# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mushroom::Context do
  subject(:ctx) { described_class.new(target: 'acme') }

  it 'initialises with sensible defaults' do
    expect(ctx.target).to eq('acme')
    expect(ctx.region).to eq('us-east-1')
    expect(ctx.account_id).to be_nil
    expect(ctx.credentials).to be_nil
    expect(ctx.discovered_buckets).to eq([])
    expect(ctx.discovered_principals).to eq([])
  end

  it 'generates a unique campaign_id per instance' do
    other = described_class.new(target: 'other')
    expect(ctx.campaign_id).not_to eq(other.campaign_id)
    expect(ctx.campaign_id).to match(/\Amushroom-[0-9a-f]{8}\z/)
  end

  it 'allows mutating account_id' do
    ctx.account_id = '123456789012'
    expect(ctx.account_id).to eq('123456789012')
  end

  it 'accepts a custom region' do
    ctx2 = described_class.new(target: 'x', region: 'eu-west-1')
    expect(ctx2.region).to eq('eu-west-1')
  end

  it 'accumulates discovered buckets and principals' do
    ctx.discovered_buckets = %w[bucket-a bucket-b]
    ctx.discovered_principals = ['arn:aws:iam::000:role/Admin']
    expect(ctx.discovered_buckets.length).to eq(2)
    expect(ctx.discovered_principals.length).to eq(1)
  end
end
