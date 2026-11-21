# frozen_string_literal: true

module Onetime
  # Redis schema versioning for idempotent, online upgrades.
  #
  # The schema marker is a single integer key. Each step below must be safe to
  # run while old records exist and must be idempotent on its own: a step only
  # stamps the marker once it has completed its (possibly empty) work. Nothing
  # here rewrites `secret:object:*` records — their exact bytes are what the
  # atomic consume compares, so rewriting them in place would break in-flight
  # reveals (DATABASE.md §8).
  module Migrate
    SCHEMA_KEY = "schema:version"
    TARGET_VERSION = 1

    # Ordered schema versions this release knows how to apply.
    STEPS = { 1 => "initial-schema" }.freeze

    module_function

    def current_version
      value = Store.redis.get(SCHEMA_KEY)
      return 0 if value.nil?

      unless value.to_s.match?(/\A\d+\z/)
        raise Error, "#{SCHEMA_KEY} is corrupt: expected an integer, got #{value.to_s[0, 32].inspect}"
      end

      value.to_i
    end

    # Reports what would be applied. Reads the marker but performs no writes.
    def dry_run
      current = current_version
      result(current, pending(current), [], true)
    end

    # Applies every pending step in order. Re-running is a no-op; a database
    # written by a newer release is refused rather than downgraded or damaged.
    def apply!
      current = current_version
      steps = pending(current)
      applied = []

      steps.each do |version, _name|
        applied << STEPS.fetch(version) if apply_step(version)
      end

      result(current_version, steps, applied, false)
    end

    def pending(current)
      if current > TARGET_VERSION
        raise Error, "database has a newer schema version (#{current}) " \
                     "than this release supports (#{TARGET_VERSION})"
      end

      STEPS.filter_map { |version, name| [version, name] if version > current }
    end
    private_class_method :pending

    def apply_step(version)
      case version
      when 1
        # The initial schema has no data to reshape: stamping the marker *is*
        # the migration. NX makes concurrent runners safe — only the runner
        # that actually writes the key reports it as applied.
        !Store.redis.set(SCHEMA_KEY, version.to_s, nx: true).nil?
      else
        raise Error, "no migration step for schema version #{version}"
      end
    end
    private_class_method :apply_step

    def result(current, steps, applied, dry_run)
      {
        current: current,
        target: TARGET_VERSION,
        planned: steps.map(&:last),
        applied: applied,
        dry_run: dry_run
      }
    end
    private_class_method :result
  end
end
