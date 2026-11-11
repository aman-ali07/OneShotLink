#!/usr/bin/env ruby
# frozen_string_literal: true

# Throughput / correctness soak for the rate limiter and the atomic reveal.
#
# Goal: prove that under concurrency (a) no secret is revealed twice and (b)
# the single-use invariant holds at load, not just in a two-request race.
#
# Usage: BASE_URL=http://127.0.0.1:3000 ruby script/loadtest.rb [secrets] [threads]
#
# Requires a running instance. This is intentionally dependency-free so it can
# run inside the production image or a CI step.

require "json"
require "net/http"
require "uri"
require "digest"

BASE = ENV.fetch("BASE_URL", "http://127.0.0.1:3000")
SECRETS = (ARGV[0] || ENV.fetch("LT_SECRETS", "200")).to_i
THREADS = (ARGV[1] || ENV.fetch("LT_THREADS", "20")).to_i

def http
  uri = URI(BASE)
  Net::HTTP.new(uri.host, uri.port).tap { |h| h.open_timeout = 5; h.read_timeout = 15 }
end

def post(path, body)
  uri = URI(BASE + path)
  req = Net::HTTP::Post.new(uri, "content-type" => "application/json")
  req.body = JSON.generate(body)
  http.request(req)
end

def get(path)
  uri = URI(BASE + path)
  http.request(Net::HTTP::Get.new(uri))
end

def create
  res = post("/api/v3/guest/conceal", secret: "load-#{Digest::SHA256.hexdigest(rand.to_s)[0, 12]}", ttl: 1800)
  raise "create failed: #{res.code} #{res.body}" unless res.code.to_i == 201

  JSON.parse(res.body)["secret_key"]
end

puts "Creating #{SECRETS} secrets over #{THREADS} threads..."
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
queue = Queue.new
keys = []

mutex = Mutex.new
creators = Array.new(THREADS) do
  Thread.new do
    loop do
      done = mutex.synchronize { queue.empty? && keys.length >= SECRETS }
      break if done

      key = create
      mutex.synchronize { keys << key if keys.length < SECRETS }
    end
  end
end
creators.each(&:join)
created_in = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
puts format("Created %d secrets in %.2fs (%.1f/s)", keys.length, created_in, keys.length / created_in)

puts "Racing #{THREADS} concurrent reveals against each secret..."
double_reveals = 0
reveal_ok = 0
reveal_fail = 0

result_mutex = Mutex.new
work = Queue.new
keys.each_slice(1) { |k| work << k.first }

started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
workers = Array.new(THREADS) do
  Thread.new do
    loop do
      key = begin
        work.pop(true)
      rescue ThreadError
        break
      end
      ok = 0
      # N concurrent attempts at the same key; exactly one may win.
      8.times.map do
        Thread.new do
          res = get("/api/v3/guest/secret/#{key}")
          result_mutex.synchronize { ok += 1 if res.code.to_i == 200 }
        end
      end.each(&:join)
      result_mutex.synchronize do
        if ok == 1
          reveal_ok += 1
        else
          double_reveals += 1
        end
        reveal_fail += 1
      end
    end
  end
end
workers.each(&:join)
reveal_in = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

puts format("Revealed in %.2fs", reveal_in)
puts "Secrets revealed exactly once: #{reveal_ok}"
puts "Secrets with wrong reveal count: #{double_reveals}"

if double_reveals.positive?
  warn "FAIL: #{double_reveals} secret(s) were not revealed exactly once"
  exit 1
end
puts "PASS: every secret was revealed exactly once under concurrent load"
