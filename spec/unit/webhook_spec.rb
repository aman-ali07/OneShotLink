# frozen_string_literal: true

require "socket"

RSpec.describe Onetime::Webhook do
  def with_env(vars)
    old = vars.keys.to_h { |key| [key, ENV[key]] }
    vars.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    old.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  describe "URL validation" do
    it "rejects non-public destinations by default" do
      with_env("WEBHOOK_ALLOW_PRIVATE" => nil) do
        ["http://127.0.0.1/x", "http://10.0.0.5/hook", "http://localhost/hook",
         "file:///etc/passwd", "https://user:pass@example.com/hook"].each do |url|
          expect { described_class.validate_url!(url) }.to raise_error(Onetime::ValidationError), url
        end
      end
    end

    it "allows a private destination when explicitly enabled for local testing" do
      with_env("WEBHOOK_ALLOW_PRIVATE" => "true") do
        expect(described_class.validate_url!("http://127.0.0.1:9/hook")).to eq("http://127.0.0.1:9/hook")
      end
    end
  end

  describe "registry and queue" do
    it "stores the signing secret encrypted and never returns it in listings" do
      with_env("WEBHOOK_ALLOW_PRIVATE" => "true") do
        created = described_class.create(
          owner_id: "cust-1",
          url: "http://127.0.0.1:9/hook",
          events: ["secret.created"],
        )
        raw = Onetime::Store.redis.hgetall(described_class.key(created[:id]))
        expect(raw["signing_secret"]).not_to include(created[:signing_secret])
        expect(JSON.parse(raw["signing_secret"])).to have_key("ciphertext")
        listed = described_class.list("cust-1").first
        expect(listed).not_to have_key(:signing_secret)
        expect(listed[:events]).to eq(["secret.created"])
      end
    end

    it "enqueues only subscribed events with metadata-only payloads" do
      with_env("WEBHOOK_ALLOW_PRIVATE" => "true") do
        described_class.create(owner_id: "cust-2", url: "http://127.0.0.1:9/hook",
                               events: ["request.revealed"])
        described_class.emit("secret.created", owner_id: "cust-2",
                             data: { identifier: "abc", secret: "SHOULD-NOT-APPEAR" })
        expect(described_class.claim).to be_empty

        described_class.emit("request.revealed", owner_id: "cust-2",
                             data: { request_key: "key-1", label: "API key" })
        items = described_class.claim
        expect(items.length).to eq(1)
        expect(items.first["payload"]).to include("request.revealed", "key-1")
        expect(items.first["payload"]).not_to include("SHOULD-NOT-APPEAR")
        expect(described_class.claim).to be_empty
      end
    end
  end

  describe "delivery" do
    it "signs the body, delivers once, and skips a replayed delivery id" do
      with_env("WEBHOOK_ALLOW_PRIVATE" => "true") do
        server = TCPServer.new("127.0.0.1", 0)
        port = server.addr[1]
        received = Queue.new
        thread = Thread.new do
          loop do
            socket = server.accept
            socket.gets
            headers = {}
            while (line = socket.gets) && line != "\r\n"
              name, value = line.split(":", 2)
              headers[name.downcase] = value.to_s.strip
            end
            body = socket.read(headers["content-length"].to_i)
            received << { headers: headers, body: body }
            socket.write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok")
            socket.close
          end
        end

        begin
          endpoint = described_class.create(
            owner_id: "cust-3",
            url: "http://127.0.0.1:#{port}/hook",
            events: ["secret.revealed"],
          )
          described_class.emit("secret.revealed", owner_id: "cust-3",
                               data: { identifier: "secret-1", kind: "text", ttl: 1800 })
          item = described_class.claim.first
          expect(described_class.deliver(item)).to eq(:delivered)

          message = received.pop
          expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', endpoint[:signing_secret], item['payload'])}"
          expect(message[:headers]["x-oneshotlink-signature"]).to eq(expected)
          expect(message[:headers]["x-oneshotlink-delivery"]).to eq(item["delivery_id"])
          expect(JSON.parse(message[:body])["event"]).to eq("secret.revealed")

          expect(described_class.deliver(item)).to eq(:skipped)
          expect(received.empty?).to be(true)
          record = Onetime::Store.redis.hgetall(described_class.delivery_key(item["delivery_id"]))
          expect(record["status"]).to eq("delivered")
        ensure
          thread.kill
          server.close
        end
      end
    end
  end
end
