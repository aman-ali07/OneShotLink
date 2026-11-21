# frozen_string_literal: true

require "open3"

RSpec.describe "Operator CLI" do
  ROOT = File.expand_path("../..", __dir__)
  CLI = File.join(ROOT, "bin", "ots")

  def ots(*args)
    Open3.capture3({ "RACK_ENV" => "test" }, RbConfig.ruby, CLI, *args, chdir: ROOT)
  end

  it "lists audit events for an operator without an HTTP endpoint" do
    Onetime::Audit.record("customer.signin", actor_id: "cust-cli", request_id: "req-cli")

    out, err, status = ots("audit", "--limit", "5")

    expect(status.exitstatus).to eq(0), err
    events = JSON.parse(out)
    expect(events.first).to include("event" => "customer.signin", "actor_id" => "cust-cli")
  end

  it "fails closed on invalid configuration before running any command" do
    env = {
      "RACK_ENV" => "test",
      "SECRET" => "x" * 40,
      "TRUSTED_PROXIES" => "not-a-cidr"
    }
    out, err, status = Open3.capture3(env, RbConfig.ruby, CLI, "health", chdir: ROOT)

    expect(status.exitstatus).not_to eq(0)
    # Depending on inherited env the CLI rejects the bad config at load time
    # ("invalid configuration") or in the health check ("config: fail" plus a
    # "Health check failed" abort). Both are a fail-closed outcome; neither
    # performs any work.
    combined = "#{out}\n#{err}"
    expect(combined).to match(/invalid configuration|config: fail/)
    expect(combined).not_to include("Status: ok")
  end

  it "records administrative migrations and backups in the audit stream" do
    out, err, status = ots("migrate", "--dry-run")
    expect(status.exitstatus).to eq(0), err
    expect(out).to include("schema:")

    Dir.mktmpdir do |dir|
      _out, err, status = ots("backup", "--out", File.join(dir, "dump.json"))
      expect(status.exitstatus).to eq(0), err
    end

    events = Onetime::Audit.recent(limit: 20).map { |entry| entry["event"] }
    expect(events).to include("admin.migrated", "admin.backup_exported")
  end

  it "attributes scheduled webhook worker runs in the audit stream" do
    _out, err, status = ots("webhooks:work", "0")
    expect(status.exitstatus).to eq(0), err

    expect(Onetime::Audit.recent(limit: 20).map { |entry| entry["event"] })
      .to include("webhook.worker_run")
  end

  it "records a role change in the audit stream" do
    customer = Onetime::Models::Customer.create(
      email: "role-cli@example.com",
      password_hash: Onetime::Password.create("a long enough password")
    )

    out, err, status = ots("customers", "set-role", "--email", "role-cli@example.com", "--role", "admin")

    expect(status.exitstatus).to eq(0), err
    expect(out).to include("role: admin")
    expect(Onetime::Audit.recent(limit: 20).map { |entry| entry["event"] })
      .to include("admin.role_changed")
    expect(customer[:id]).not_to be_nil
  end
end
