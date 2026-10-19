# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mushroom::Credentials do
  let(:raw_key) { 'ASIAEXAMPLESECRET' }
  let(:credentials) do
    described_class.from_imds(
      {
        'AccessKeyId' => raw_key,
        'SecretAccessKey' => 'secret',
        'Token' => 'token',
        'Expiration' => (Time.now.utc + 3600).iso8601
      },
      source_arn: 'arn:aws:iam::123456789012:role/example'
    )
  end

  it 'keeps credential fields and converts to AWS credentials' do
    expect(credentials.access_key_id).to eq(raw_key)
    expect(credentials.to_aws).to be_a(Aws::Credentials)
    expect(credentials.expired?).to be(false)
  end

  it 'redacts the full access key' do
    expect(credentials.redacted).not_to include(raw_key)
    expect(credentials.redacted).to include('ASIA')
  end

  it 'detects expiration' do
    expect(credentials.with(expiration: Time.now.utc - 1).expired?).to be(true)
  end
end
