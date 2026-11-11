# frozen_string_literal: true

RSpec.describe Onetime::Ids do
  it "generates URL-safe identifiers with at least 128 bits of entropy" do
    id = described_class.extid
    expect(id.length).to be >= 22
    expect(id).to match(/\A[A-Za-z0-9_-]+\z/)
  end

  it "does not repeat across 1,000 identifiers" do
    ids = Array.new(1_000) { described_class.extid }
    expect(ids.uniq.length).to eq(1_000)
  end

  it "normalizes email indexes case-insensitively" do
    expect(described_class.opaque_index("A@Example.com"))
      .to eq(described_class.opaque_index("a@example.com"))
  end

  it "does not expose the original value in the index" do
    expect(described_class.opaque_index("a@example.com")).not_to include("example")
  end
end
