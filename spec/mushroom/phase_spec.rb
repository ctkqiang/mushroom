# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mushroom::Phase do
  it 'runs registered cleanups in reverse order even when execution raises' do
    order = []
    subclass = Class.new(described_class) do
      define_method(:execute) do
        with_cleanup { order << :first }
        with_cleanup { order << :second }
        raise Mushroom::PhaseAborted, 'stop'
      end
    end
    config = Mushroom::Config.load
    context = Mushroom::Context.new(target: 'example')
    logger = Mushroom::Logger.new(path: File::NULL, io: StringIO.new)
    store = Mushroom::VerdictStore.new(path: File::NULL)
    phase = subclass.new(context: context, config: config, logger: logger, verdict_store: store)
    expect { phase.call }.to raise_error(Mushroom::PhaseAborted)
    expect(order).to eq(%i[second first])
    store.close
    logger.close
  end
end
