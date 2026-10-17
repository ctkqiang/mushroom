# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mushroom::Config do
  describe '.load' do
    it 'returns dry_run: true by default' do
      config = described_class.load
      expect(config.dry_run?).to be(true)
    end

    it 'returns cleanup: true by default' do
      config = described_class.load
      expect(config.cleanup?).to be(true)
    end

    it 'overrides defaults with keyword overrides' do
      config = described_class.load(overrides: { dry_run: false, timeframe_hours: 2 })
      expect(config.dry_run?).to be(false)
      expect(config[:timeframe_hours]).to eq(2)
    end

    it 'accepts string keys in overrides and normalises them to symbols' do
      config = described_class.load(overrides: { 'dry_run' => false })
      expect(config.dry_run?).to be(false)
    end

    it 'ignores a missing YAML file gracefully' do
      config = described_class.load(path: '/nonexistent/path.yml')
      expect(config.dry_run?).to be(true)
    end

    it 'loads YAML values and overrides win over file values', :tmp do |_example|
      Dir.mktmpdir do |dir|
        file = File.join(dir, 'settings.yml')
        File.write(file, "dry_run: false\ntimeframe_hours: 4\n")
        config = described_class.load(path: file, overrides: { dry_run: true })
        expect(config.dry_run?).to be(true)
        expect(config[:timeframe_hours]).to eq(4)
      end
    end
  end

  describe '#assert_safe!' do
    it 'raises ConfigError for a denied account' do
      config = described_class.load(overrides: { deny_accounts: ['123456789012'] })
      expect { config.assert_safe!(account_id: '123456789012') }
        .to raise_error(Mushroom::ConfigError, /deny list/)
    end

    it 'raises ConfigError when account is not in a non-empty allow list' do
      config = described_class.load(overrides: { allow_accounts: ['111111111111'] })
      expect { config.assert_safe!(account_id: '999999999999') }
        .to raise_error(Mushroom::ConfigError, /allow list/)
    end

    it 'allows an account that is in the allow list' do
      config = described_class.load(overrides: { allow_accounts: ['123456789012'] })
      expect { config.assert_safe!(account_id: '123456789012') }.not_to raise_error
    end

    it 'allows any account when both lists are empty' do
      config = described_class.load
      expect { config.assert_safe!(account_id: '999999999999') }.not_to raise_error
    end

    it 'deny list takes precedence over allow list for the same account' do
      config = described_class.load(
        overrides: { allow_accounts: ['123456789012'], deny_accounts: ['123456789012'] }
      )
      expect { config.assert_safe!(account_id: '123456789012') }
        .to raise_error(Mushroom::ConfigError, /deny list/)
    end
  end

  describe '#[]' do
    it 'returns the value for a known key' do
      config = described_class.load(overrides: { tag_prefix: 'MyTag' })
      expect(config[:tag_prefix]).to eq('MyTag')
    end

    it 'raises KeyError for an unknown key' do
      config = described_class.load
      expect { config[:nonexistent_key] }.to raise_error(KeyError)
    end
  end

  describe '#to_h' do
    it 'returns a plain Hash of all settings' do
      config = described_class.load
      h = config.to_h
      expect(h).to be_a(Hash)
      expect(h[:dry_run]).to be(true)
    end

    it 'returns a dup — mutations do not affect the config' do
      config = described_class.load
      h = config.to_h
      h[:dry_run] = false
      expect(config.dry_run?).to be(true)
    end
  end
end
