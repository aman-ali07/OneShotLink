# frozen_string_literal: true

# The free-tier runbooks are part of the security control: an invalid backup
# encryption command means no off-platform backup exists at all (SA-new doc gate).
RSpec.describe "Security documentation gates" do
  DOCS = %w[FREE_TIER_DEPLOYMENT_PLAN.md INFRASTRUCTURE_SECURITY.md].freeze

  it "does not prescribe an unsupported OpenSSL AEAD encryption command" do
    DOCS.each do |name|
      body = File.read(File.expand_path("../../#{name}", __dir__))
      expect(body).not_to include("openssl enc -aes-256-gcm"), name
    end
  end

  it "never evals operator-supplied CIDRs in the host firewall helper" do
    body = File.read(File.expand_path("../../script/host-firewall.sh", __dir__))
    expect(body).not_to match(/\beval\b/), "root firewall helper must not eval generated commands"
    expect(body).to include("ipaddress.ip_network"), "CIDRs must be validated before use"
  end

  it "prescribes an integrity-protected, passphrase-from-stdin backup encryption command" do
    body = File.read(File.expand_path("../../INFRASTRUCTURE_SECURITY.md", __dir__))
    expect(body).to include("gpg --symmetric --cipher-algo AES256")
    expect(body).to include("--passphrase-fd 0")
  end
end
