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

    it "rejects IPv4-mapped IPv6 addresses that point into private space" do
      with_env("WEBHOOK_ALLOW_PRIVATE" => nil) do
        expect(described_class.private_address?("::ffff:169.254.169.254")).to be(true)
        expect(described_class.private_address?("::ffff:127.0.0.1")).to be(true)
      end
    end

    it "stores the validated address so delivery cannot re-resolve the hostname" do
      with_env("WEBHOOK_ALLOW_PRIVATE" => nil) do
        created = described_class.create(
          owner_id: "cust-pin",
          url: "http://93.184.216.34/hook",
          events: ["secret.created"],
        )
        raw = Onetime::Store.redis.hgetall(described_class.key(created[:id]))
        expect(raw["resolved_ip"]).to eq("93.184.216.34")
      end
    end
  end

  describe "IP pinning" do
    it "uses the stored address at delivery and refuses a private one" do
      with_env("WEBHOOK_ALLOW_PRIVATE" => nil) do
        endpoint = { "url" => "http://rebind.invalid/hook", "resolved_ip" => "93.184.216.34" }
        expect(described_class.pinned_address(endpoint)).to eq("93.184.216.34")

        endpoint["resolved_ip"] = "127.0.0.1"
        expect { described_class.pinned_address(endpoint) }.to raise_error(Onetime::ValidationError)
      end
    end

    it "connects to the pinned address instead of re-resolving the host" do
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]
      received = Queue.new
      thread = Thread.new do
        socket = server.accept
        headers = {}
        while (line = socket.gets) && line != "\r\n"
          name, value = line.split(":", 2)
          headers[name.downcase] = value.to_s.strip
        end
        received << headers
        socket.write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok")
        socket.close
      end

      begin
        uri = URI("http://unresolvable.invalid:#{port}/hook")
        request = Net::HTTP::Post.new(uri)
        request.body = "{}"
        expect(described_class.post(uri, request, "127.0.0.1")).to eq(200)
        expect(received.pop["host"]).to include("unresolvable.invalid")
      ensure
        thread.kill
        server.close
      end
    end

    it "ignores an environment HTTP proxy so the pin still governs the socket" do
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]
      received = Queue.new
      thread = Thread.new do
        socket = server.accept # reaching accept proves the pin, not a proxy, chose the socket
        received << true
        socket.write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok")
        socket.close
      end

      begin
        uri = URI("http://unresolvable.invalid:#{port}/hook")
        request = Net::HTTP::Post.new(uri)
        request.body = "{}"
        # A proxy would re-resolve unresolvable.invalid itself and defeat ipaddr.
        with_env("http_proxy" => "http://127.0.0.1:1", "HTTP_PROXY" => "http://127.0.0.1:1",
                 "no_proxy" => nil, "NO_PROXY" => nil) do
          expect(described_class.post(uri, request, "127.0.0.1")).to eq(200)
        end
        expect(received.pop).to be(true)
      ensure
        thread.kill
        server.close
      end
    end
  end

  describe "queue retention" do
    it "bounds delivery records and prunes queue entries older than the TTL (D-queue)" do
      endpoint = described_class.create(
        owner_id: "cust-ttl", url: "https://example.com/hook", events: ["secret.created"]
      )
      described_class.emit("secret.created", owner_id: "cust-ttl",
                           data: { identifier: "x", kind: "text", ttl: 60 })
      item = JSON.parse(Onetime::Store.redis.zrange(described_class::QUEUE_KEY, 0, -1).fetch(0))
      expect(Onetime::Store.redis.ttl(described_class.delivery_key(item["delivery_id"])))
        .to be_between(1, described_class::DELIVERY_TTL)

      stale = JSON.generate("delivery_id" => "stale", "endpoint_id" => endpoint[:id], "payload" => "{}")
      Onetime::Store.redis.zadd(
        described_class::QUEUE_KEY,
        Time.now.to_f - described_class::QUEUE_TTL - 1,
        stale
      )

      claimed = described_class.claim
      expect(claimed.map { |entry| entry["delivery_id"] }).to include(item["delivery_id"])
      expect(claimed.map { |entry| entry["delivery_id"] }).not_to include("stale")
      expect(Onetime::Store.redis.zscore(described_class::QUEUE_KEY, stale)).to be_nil
    end

    it "does not resurrect a delivery record for a deleted endpoint" do
      endpoint = described_class.create(
        owner_id: "cust-del", url: "https://example.com/hook", events: ["secret.created"]
      )
      described_class.emit("secret.created", owner_id: "cust-del",
                           data: { identifier: "x", kind: "text", ttl: 60 })
      item = described_class.claim(limit: 10).first
      delivery_key = described_class.delivery_key(item.fetch("delivery_id"))
      expect(Onetime::Store.redis.ttl(delivery_key)).to be > 0

      # What DeleteAccount does: remove the endpoint and its delivery hashes,
      # but a queued event can still be claimed afterwards.
      described_class.delete(owner_id: "cust-del", id: endpoint[:id])
      Onetime::Store.redis.del(delivery_key)

      expect(described_class.deliver(item)).to eq(:skipped)
      expect(Onetime::Store.redis.exists?(delivery_key)).to be(false)
    end
  end

  describe "deliveries" do
    it "lists only the requested endpoint's deliveries, and none for a foreign id" do
      a = described_class.create(owner_id: "cust-deliv", url: "http://93.184.216.34/a", events: ["secret.created"])
      b = described_class.create(owner_id: "cust-deliv", url: "http://93.184.216.34/b", events: ["secret.created"])
      Onetime::Store.redis.hset(described_class.delivery_key("d-a"), {
        "endpoint_id" => a[:id], "event" => "secret.created", "status" => "delivered"
      })
      Onetime::Store.redis.hset(described_class.delivery_key("d-b"), {
        "endpoint_id" => b[:id], "event" => "secret.created", "status" => "delivered"
      })

      expect(described_class.deliveries("cust-deliv", id: a[:id]).map { |d| d[:id] }).to eq(["d-a"])
      expect(described_class.deliveries("cust-deliv", id: "someone-elses-id")).to be_empty
      expect(described_class.deliveries("cust-deliv").map { |d| d[:id] }).to contain_exactly("d-a", "d-b")
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
    it "does not create a permanent delivery key for a malformed queue item" do
      # A missing delivery_id raises before `inflight` is assigned; the rescue
      # must not HSET a TTL-less `webhook:delivery:` record for the nil id.
      expect(described_class.deliver({ "endpoint_id" => "x", "payload" => "{}" })).to eq(:failed)
      expect(Onetime::Store.redis.exists?(described_class.delivery_key(nil))).to be(false)
    end

    it "retries a failed delivery instead of suppressing the replayed id" do
      with_env("WEBHOOK_ALLOW_PRIVATE" => "true") do
        server = TCPServer.new("127.0.0.1", 0)
        port = server.addr[1]
        calls = Queue.new
        thread = Thread.new do
          2.times do |i|
            socket = server.accept
            socket.gets until (line = socket.gets).nil? || line == "\r\n"
            calls << i
            code = i.zero? ? "500" : "200"
            socket.write("HTTP/1.1 #{code} OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok")
            socket.close
          end
        end

        begin
          described_class.create(owner_id: "cust-retry", url: "http://127.0.0.1:#{port}/hook",
                                 events: ["secret.created"])
          described_class.emit("secret.created", owner_id: "cust-retry",
                               data: { identifier: "retry-1", kind: "text", ttl: 60 })
          item = described_class.claim.first
          expect(described_class.deliver(item)).to eq(:retrying)
          expect(described_class.deliver(item)).to eq(:delivered)
          expect(calls.length).to eq(2)
          expect(described_class.deliver(item)).to eq(:skipped)
        ensure
          thread.kill
          server.close
        end
      end
    end

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

  describe "emit efficiency" do
    it "uses a constant number of round trips regardless of endpoint count" do
      3.times do |i|
        described_class.create(
          owner_id: "cust-perf", url: "https://example.com/hook-#{i}", events: ["secret.created"]
        )
      end
      allow(Onetime::Store.redis).to receive(:pipelined).and_call_original

      described_class.emit("secret.created", owner_id: "cust-perf",
                           data: { identifier: "x", kind: "text", ttl: 60 })

      # prune+lookup, endpoint fetch, and all writes: three batches for ANY N.
      expect(Onetime::Store.redis).to have_received(:pipelined).exactly(3).times
      expect(Onetime::Store.redis.zrange(described_class::QUEUE_KEY, 0, -1).length).to eq(3)
    end
  end
end
