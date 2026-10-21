# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mushroom::Logger do
  def build_logger(path: File::NULL, io: StringIO.new, level: :debug)
    described_class.new(path: path, io: io, level: level)
  end

  after { |example| example.metadata[:logger]&.close }

  it 'writes a structured JSON line to the file sink' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'audit.jsonl')
      logger = build_logger(path: path)
      logger.info('hello', key: 'val')
      logger.close
      line = JSON.parse(File.readlines(path).first)
      expect(line['message']).to eq('hello')
      expect(line['key']).to eq('val')
      expect(line['level']).to eq('info')
      expect(Time.iso8601(line['at'])).to be_a(Time)
    end
  end

  it 'writes a human-readable line to the IO sink' do
    io = StringIO.new
    logger = build_logger(io: io)
    logger.info('test message')
    logger.close
    expect(io.string).to include('test message')
  end

  it 'suppresses messages below the configured level' do
    io = StringIO.new
    logger = build_logger(io: io, level: :warn)
    logger.info('should not appear')
    logger.warn('should appear')
    logger.close
    expect(io.string).not_to include('should not appear')
    expect(io.string).to include('should appear')
  end

  it 'appends multiple lines without truncation' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'audit.jsonl')
      logger = build_logger(path: path)
      logger.info('line one')
      logger.warn('line two')
      logger.close
      lines = File.readlines(path)
      expect(lines.length).to eq(2)
    end
  end

  it 'does not raise on close when already closed' do
    logger = build_logger
    logger.close
    expect { logger.close }.not_to raise_error
  end

  it 'creates parent directories automatically' do
    Dir.mktmpdir do |dir|
      nested = File.join(dir, 'deep', 'nested', 'audit.jsonl')
      logger = build_logger(path: nested)
      logger.info('nested')
      logger.close
      expect(File.exist?(nested)).to be(true)
    end
  end
end
