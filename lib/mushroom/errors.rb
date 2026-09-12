# frozen_string_literal: true

module Mushroom
  class Error < StandardError; end

  class ConfigError           < Error; end
  class MissingStateError     < Error; end
  class PhaseAborted          < Error; end
  class ExploitFailed         < Error; end
  class InsufficientPrivilege < Error; end

  module Harvest
    class SsrfFailed      < Mushroom::Error; end
    class ImdsUnreachable < Mushroom::Error; end
    class CredentialLeak  < Mushroom::Error; end
  end
end
