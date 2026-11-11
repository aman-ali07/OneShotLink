# frozen_string_literal: true

require "logger"

require_relative "onetime/version"
require_relative "onetime/config"
require_relative "onetime/errors"
require_relative "onetime/ids"
require_relative "onetime/crypto"
require_relative "onetime/password"
require_relative "onetime/store"
require_relative "onetime/limiter"
require_relative "onetime/models/customer"
require_relative "onetime/models/session"
require_relative "onetime/models/secret"
require_relative "onetime/logic/conceal_secret"
require_relative "onetime/logic/reveal_secret"
require_relative "onetime/logic/sign_up"
require_relative "onetime/logic/sign_in"

module Onetime
  # Structured-ish logging without secret material. Callers log identifiers and
  # status only; nothing here inspects request bodies.
  def self.logger
    @logger ||= begin
      level = %w[debug info warn error fatal].include?(Config.log_level.to_s) ? Config.log_level : :info
      Logger.new($stderr, level: level).tap do |log|
        log.formatter = proc do |severity, time, _progname, message|
          %(#{time.utc.iso8601} #{severity} #{message}\n)
        end
      end
    end
  end
end
