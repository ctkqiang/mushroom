# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mushroom::Campaign do
  def build_campaign(directory)
    config = Mushroom::Config.load(
      overrides: {
        verdict_path: File.join(directory, 'verdicts.jsonl'),
        audit_path: File.join(directory, 'audit.jsonl')
      }
    )
    logger = Mushroom::Logger.new(path: config[:audit_path], io: StringIO.new)
    [described_class.new(target: 'acme-corp', config: config, logger: logger), logger]
  end

  it 'runs all five distinct baseline evasion scenarios without network access' do
    Dir.mktmpdir do |directory|
      campaign, logger = build_campaign(directory)
      expect { campaign.run }.not_to raise_error
      scenarios = campaign.map(&:scenario)
      expect(scenarios).to match_array(
        %w[service_role_attribution cloud_control_api alt_iam_actions identity_switch time_delay]
      )
      expect(campaign.report.fetch(:summary).fetch(:bypassed)).to eq(5)
      lines = File.readlines(File.join(directory, 'verdicts.jsonl'))
      expect(lines.length).to eq(5)
      expect(lines.map { |line| JSON.parse(line).fetch('original_rule_would_fire') }.uniq).to eq([false])
      campaign.close
      logger.close
    end
  end

  it 'refuses a denied account during preflight' do
    Dir.mktmpdir do |directory|
      campaign, logger = build_campaign(directory)
      campaign.context.account_id = '123456789012'
      denied = Mushroom::Config.load(
        overrides: { deny_accounts: ['123456789012'], audit_path: File.join(directory, 'deny.jsonl') }
      )
      phase = Mushroom::Phases::Recon.new(context: campaign.context, config: denied, logger: logger,
                                          verdict_store: campaign.verdict_store)
      expect { phase.call }.to raise_error(Mushroom::ConfigError)
      campaign.close
      logger.close
    end
  end
end
