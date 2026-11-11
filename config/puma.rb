# frozen_string_literal: true

require_relative "../lib/onetime"

port ENV.fetch("PORT", 3000).to_i
environment ENV.fetch("RACK_ENV", "development")
threads Integer(ENV.fetch("PUMA_MIN_THREADS", 1)), Integer(ENV.fetch("PUMA_MAX_THREADS", 5))

# Optional multi-process mode. The app is stateless (Redis holds all state), so
# workers are safe; reset the inherited Redis socket after fork.
workers = Integer(ENV.fetch("WEB_CONCURRENCY", 0))
if workers.positive?
  workers workers
  preload_app!
  on_worker_boot { Onetime::Store.reset! }
end

# Fail fast if the process cannot answer within the platform's grace period.
worker_timeout Integer(ENV.fetch("PUMA_WORKER_TIMEOUT", 60)) if respond_to?(:worker_timeout)
