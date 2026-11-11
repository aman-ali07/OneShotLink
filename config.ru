# frozen_string_literal: true

require_relative "lib/onetime"
require_relative "lib/onetime/web/app"
require_relative "lib/onetime/web/request_logger"
require_relative "lib/onetime/web/head_requests"

# Fail fast: an invalid deployment must not boot and must not serve traffic.
begin
  Onetime::Config.validate!
rescue Onetime::Config::Error => e
  warn "onetime: cannot boot: #{e.message}"
  exit 1
end

Onetime.logger.info(
  "boot version=#{Onetime::VERSION} env=#{ENV.fetch('RACK_ENV', 'development')} " \
  "auth_mode=#{Onetime::Config.auth_mode} ui=#{Onetime::Config.ui_enabled?} ssl=#{Onetime::Config.ssl?}"
)

use Onetime::Web::HeadRequests
use Onetime::Web::RequestLogger
run Onetime::Web::App
