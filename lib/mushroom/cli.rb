# frozen_string_literal: true

require 'optparse'
require 'fileutils'

module Mushroom
  # Command-line front-end.  Parses ARGV and dispatches to Campaign.
  #
  # Usage:
  #   bundle exec bin/mushroom campaign --target ACCOUNT_ALIAS [options]
  class CLI
    BANNER = <<~BANNER.freeze
      Mushroom – CloudFormation/IAM privilege-escalation detection auditor
      Version: #{Mushroom::VERSION}

      Usage: mushroom <command> [options]

      Commands:
        campaign    Run the full four-phase simulation against a target

      Global options:
    BANNER

    def self.start(argv)
      new(argv).run
    end

    def initialize(argv)
      @argv    = argv.dup
      @options = {
        target: nil,
        live: false,
        ssrf_endpoint: nil,
        template_bucket: nil,
        execution_role_arn: nil,
        allow_account: [],
        deny_account: [],
        config_file: nil,
        verdict_path: 'tmp/mushroom-verdicts.jsonl',
        audit_path: 'tmp/mushroom-audit.jsonl'
      }
    end

    def run
      command = @argv.shift
      case command
      when 'campaign'
        run_campaign
      when nil, '--help', '-h'
        puts BANNER
        puts parser
      else
        warn "Unknown command: #{command}"
        exit 1
      end
    end

    private

    def run_campaign
      parser.parse!(@argv)

      unless @options[:target]
        warn 'Error: --target is required'
        exit 1
      end

      config = build_config
      FileUtils.mkdir_p('tmp')

      logger   = Logger.new(path: config[:audit_path])
      campaign = Campaign.new(target: @options[:target], config: config, logger: logger)

      begin
        campaign.run
        report = campaign.report
        puts "\n=== Mushroom Campaign Report ==="
        puts "Campaign ID : #{report[:campaign_id]}"
        puts "Target      : #{report[:target]}"
        puts "Total       : #{report.dig(:summary, :total)}"
        puts "Bypassed    : #{report.dig(:summary, :bypassed)}"
        puts "Detected    : #{report.dig(:summary, :detected)}"
        puts "\nVerdicts written to: #{config[:verdict_path]}"
        puts "Audit log written to: #{config[:audit_path]}"
      ensure
        campaign.close
        logger.close
      end
    end

    def build_config
      Config.load(
        path: @options[:config_file],
        overrides: {
          dry_run: !@options[:live],
          ssrf_endpoint: @options[:ssrf_endpoint],
          template_bucket: @options[:template_bucket],
          execution_role_arn: @options[:execution_role_arn],
          allow_accounts: @options[:allow_account],
          deny_accounts: @options[:deny_account],
          verdict_path: @options[:verdict_path],
          audit_path: @options[:audit_path]
        }
      )
    end

    def parser # rubocop:disable Metrics/MethodLength
      @parser ||= OptionParser.new do |o|
        o.banner = BANNER

        o.on('--target TARGET', 'Target name / alias (required)') do |v|
          @options[:target] = v
        end

        o.on('--live', 'Disable dry-run and make real AWS calls (dangerous)') do
          @options[:live] = true
        end

        o.on('--ssrf-endpoint URL', 'SSRF endpoint URL for IMDS harvesting') do |v|
          @options[:ssrf_endpoint] = v
        end

        o.on('--template-bucket BUCKET', 'S3 bucket for CloudFormation templates') do |v|
          @options[:template_bucket] = v
        end

        o.on('--execution-role-arn ARN', 'ARN of the CFN service execution role') do |v|
          @options[:execution_role_arn] = v
        end

        o.on('--allow-account ID', 'Permit running against this account (repeatable)') do |v|
          @options[:allow_account] << v
        end

        o.on('--deny-account ID', 'Deny running against this account (repeatable)') do |v|
          @options[:deny_account] << v
        end

        o.on('-c', '--config FILE', 'Path to settings YAML') do |v|
          @options[:config_file] = v
        end

        o.on('--verdict-path PATH', 'Override verdict JSONL path') do |v|
          @options[:verdict_path] = v
        end

        o.on('--audit-path PATH', 'Override audit JSONL path') do |v|
          @options[:audit_path] = v
        end

        o.on('-h', '--help', 'Show this help') do
          puts o
          exit
        end

        o.on('-v', '--version', 'Print version') do
          puts "Mushroom #{Mushroom::VERSION}"
          exit
        end
      end
    end
  end
end
