# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Mushroom error hierarchy' do
  it 'all custom errors inherit from Mushroom::Error' do
    leaf_classes = [
      Mushroom::ConfigError,
      Mushroom::MissingStateError,
      Mushroom::PhaseAborted,
      Mushroom::ExploitFailed,
      Mushroom::InsufficientPrivilege,
      Mushroom::Harvest::SsrfFailed,
      Mushroom::Harvest::ImdsUnreachable,
      Mushroom::Harvest::CredentialLeak
    ]
    leaf_classes.each do |klass|
      expect(klass.ancestors).to include(Mushroom::Error),
                                 "Expected #{klass} to inherit from Mushroom::Error"
    end
  end

  it 'Mushroom::Error itself inherits from StandardError' do
    expect(Mushroom::Error.ancestors).to include(StandardError)
  end

  it 'each error carries a message' do
    err = Mushroom::ConfigError.new('boom')
    expect(err.message).to eq('boom')
  end

  it 'Harvest errors are rescuable as Mushroom::Error' do
    expect { raise Mushroom::Harvest::SsrfFailed, 'no endpoint' }
      .to raise_error(Mushroom::Error)
  end
end
