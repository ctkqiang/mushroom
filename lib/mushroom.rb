# frozen_string_literal: true

# Ruby 3.3 moved Logger into a bundled gem; require it explicitly before
# any library that references the ::Logger constant at load time
# (notably Seahorse::Client::NetHttp::ConnectionPool).
require 'logger'
require 'securerandom'
require 'json'

# AWS SDKs – require under bundler context before other files need them
require 'aws-sdk-cloudformation'
require 'aws-sdk-iam'
require 'aws-sdk-cloudcontrolapi'
require 'aws-sdk-sts'
require 'aws-sdk-s3'

# Core value objects and infrastructure
require_relative 'mushroom/version'
require_relative 'mushroom/errors'
require_relative 'mushroom/config'
require_relative 'mushroom/logger'
require_relative 'mushroom/credentials'
require_relative 'mushroom/verdict'
require_relative 'mushroom/verdict_store'
require_relative 'mushroom/context'
require_relative 'mushroom/aws_clients'
require_relative 'mushroom/phase'

# Recon
require_relative 'mushroom/recon/s3_enumerator'
require_relative 'mushroom/recon/account_id_prober'
require_relative 'mushroom/recon/principal_bruteforcer'

# Harvest
require_relative 'mushroom/harvest/ssrf_client'
require_relative 'mushroom/harvest/imds_stealer'

# Discovery
require_relative 'mushroom/discovery/identity_mapper'
require_relative 'mushroom/discovery/permission_fuzzer'

# Exploit strategies
require_relative 'mushroom/exploit/strategy'
require_relative 'mushroom/exploit/service_role'
require_relative 'mushroom/exploit/cloud_control'
require_relative 'mushroom/exploit/alt_iam_actions'
require_relative 'mushroom/exploit/identity_switch'
require_relative 'mushroom/exploit/time_delay'

# Phase orchestrators (loaded after strategies they reference)
require_relative 'mushroom/phases/recon'
require_relative 'mushroom/phases/harvest'
require_relative 'mushroom/phases/discovery'
require_relative 'mushroom/phases/exploit'

# Top-level orchestrator and CLI
require_relative 'mushroom/campaign'
require_relative 'mushroom/cli'
