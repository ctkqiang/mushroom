# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mushroom::Harvest::ImdseStealer do
  def build_stealer(overrides = {})
    config = Mushroom::Config.load(overrides: overrides)
    logger = Mushroom::Logger.new(path: File::NULL, io: StringIO.new)
    [described_class.new(config: config, logger: logger), logger]
  end

  def null_ssrf_client
    instance_double('Mushroom::Harvest::SsrfClient',
                    fetch_credential_names: nil,
                    fetch_credentials_for: nil)
  end

  describe '#steal in dry_run mode' do
    it 'returns a Credentials object without calling the SSRF client' do
      stealer, logger = build_stealer
      ssrf = null_ssrf_client
      expect(ssrf).not_to receive(:fetch_credential_names)

      creds = stealer.steal(ssrf_client: ssrf)
      expect(creds).to be_a(Mushroom::Credentials)
      logger.close
    end

    it 'mock credentials are not expired' do
      stealer, logger = build_stealer
      creds = stealer.steal(ssrf_client: null_ssrf_client)
      expect(creds.expired?).to be(false)
      logger.close
    end

    it 'mock access key is redacted correctly' do
      stealer, logger = build_stealer
      creds = stealer.steal(ssrf_client: null_ssrf_client)
      expect(creds.redacted).not_to include(creds.access_key_id)
      expect(creds.redacted).to include('ASIA')
      logger.close
    end
  end

  describe '#steal in live mode — error paths' do
    it 'raises ImdsUnreachable when SSRF returns no credential names' do
      stealer, logger = build_stealer(dry_run: false)
      ssrf = instance_double('Mushroom::Harvest::SsrfClient',
                             fetch_credential_names: nil)
      expect { stealer.steal(ssrf_client: ssrf) }
        .to raise_error(Mushroom::Harvest::ImdsUnreachable, /No credential list/)
      logger.close
    end

    it 'raises ImdsUnreachable when credential body is empty' do
      stealer, logger = build_stealer(dry_run: false)
      ssrf = instance_double('Mushroom::Harvest::SsrfClient',
                             fetch_credential_names: "\n")
      expect { stealer.steal(ssrf_client: ssrf) }
        .to raise_error(Mushroom::Harvest::ImdsUnreachable, /empty credential list/)
      logger.close
    end

    it 'raises ImdsUnreachable when the credentials JSON cannot be fetched' do
      stealer, logger = build_stealer(dry_run: false)
      ssrf = instance_double('Mushroom::Harvest::SsrfClient',
                             fetch_credential_names: "MyRole\n",
                             fetch_credentials_for: nil)
      expect { stealer.steal(ssrf_client: ssrf) }
        .to raise_error(Mushroom::Harvest::ImdsUnreachable, /No credentials for role/)
      logger.close
    end

    it 'raises ImdsUnreachable on malformed JSON in the credentials body' do
      stealer, logger = build_stealer(dry_run: false)
      ssrf = instance_double('Mushroom::Harvest::SsrfClient',
                             fetch_credential_names: "MyRole\n",
                             fetch_credentials_for: '{not valid json}')
      expect { stealer.steal(ssrf_client: ssrf) }
        .to raise_error(Mushroom::Harvest::ImdsUnreachable, /Failed to parse IMDS JSON/)
      logger.close
    end
  end
end
