# frozen_string_literal: true

RSpec.describe Onetime::Limiter do
  let(:scope) { "test-#{SecureRandom.hex(4)}" }

  it "allows requests up to the limit, then raises" do
    3.times { described_class.check!(scope, scope: :conceal, limit: 3, window: 10) }
    expect { described_class.check!(scope, scope: :conceal, limit: 3, window: 10) }
      .to raise_error(Onetime::RateLimited)
  end

  it "keeps scopes independent" do
    3.times { described_class.check!(scope, scope: :conceal, limit: 3, window: 10) }
    expect { described_class.check!(scope, scope: :reveal, limit: 3, window: 10) }
      .not_to raise_error
  end

  it "resets after the window expires" do
    described_class.check!(scope, scope: :reveal, limit: 1, window: 1)
    expect { described_class.check!(scope, scope: :reveal, limit: 1, window: 1) }
      .to raise_error(Onetime::RateLimited)
    sleep 1.1
    expect { described_class.check!(scope, scope: :reveal, limit: 1, window: 1) }
      .not_to raise_error
  end
end
