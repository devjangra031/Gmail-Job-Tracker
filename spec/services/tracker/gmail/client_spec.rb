require "rails_helper"

RSpec.describe Tracker::Gmail::Client do
  let(:sleeps) { [] }
  let(:service) { Google::Apis::GmailV1::GmailService.new.tap { |s| s.authorization = "test-token" } }
  let(:client) { described_class.new(service: service, max_retries: 3, requests_per_second: 0, sleeper: ->(s) { sleeps << s }) }
  let(:list_url) { %r{https://gmail\.googleapis\.com/gmail/v1/users/me/messages\?} }

  def json(body = nil, status: 200, **fields)
    body ||= fields
    { status: status, headers: { "Content-Type" => "application/json" }, body: body.to_json }
  end

  it "builds a query covering whole local days, inclusive of the end date" do
    query = described_class.query_for(date_from: Date.new(2026, 7, 1), date_to: Date.new(2026, 7, 31), base: "label:x")

    after = Time.zone.parse("2026-07-01 00:00").to_i
    before = Time.zone.parse("2026-08-01 00:00").to_i
    expect(query).to eq("label:x after:#{after} before:#{before}")
  end

  it "follows pagination" do
    # WebMock tries the most recently declared stub first, so the page-2 stub goes last.
    stub_request(:get, list_url).with(query: hash_including("q" => "x"))
      .to_return(json(messages: [ { id: "a" }, { id: "b" } ], nextPageToken: "p2"))
    stub_request(:get, list_url).with(query: hash_including("q" => "x", "pageToken" => "p2"))
      .to_return(json(messages: [ { id: "c" } ]))

    expect(client.message_ids("x")).to eq(%w[a b c])
  end

  it "returns no ids for an empty result" do
    stub_request(:get, list_url).to_return(json(resultSizeEstimate: 0))

    expect(client.message_ids("x")).to eq([])
  end

  it "fetches a full message and decodes the base64url body" do
    stub_request(:get, "https://gmail.googleapis.com/gmail/v1/users/me/messages/m1?format=full")
      .to_return(json(id: "m1", threadId: "t1", internalDate: "1758520000000",
                      payload: { mimeType: "text/plain", body: { data: Base64.urlsafe_encode64("Hello ✓") } }))

    message = client.message("m1")

    expect(message.payload.body.data.force_encoding("UTF-8")).to eq("Hello ✓")
  end

  it "backs off exponentially on 429 and 5xx, then succeeds" do
    stub_request(:get, list_url)
      .to_return(json({ error: { code: 429, message: "Too many" } }, status: 429))
      .then.to_return(json({ error: { code: 503, message: "Unavailable" } }, status: 503))
      .then.to_return(json(messages: [ { id: "a" } ]))

    expect(client.message_ids("x")).to eq(%w[a])
    expect(sleeps).to eq([ 2, 4 ])
  end

  it "treats Gmail's 403 rateLimitExceeded as a rate limit" do
    stub_request(:get, list_url)
      .to_return(json({ error: { code: 403, message: "User-rate limit exceeded", errors: [ { reason: "userRateLimitExceeded" } ] } }, status: 403))
      .then.to_return(json(messages: []))

    client.message_ids("x")

    expect(sleeps).to eq([ 2 ])
  end

  it "treats Gmail's per-minute 'Quota exceeded' 403 as a rate limit (seen on a real sync)" do
    message = "Quota exceeded for quota metric 'Total Query Cost' and limit 'Units per minute per user' " \
              "of service 'gmail.googleapis.com'"
    stub_request(:get, list_url)
      .to_return(json({ error: { code: 403, message: message, status: "PERMISSION_DENIED",
                                 details: [ { "@type": "type.googleapis.com/google.rpc.ErrorInfo", reason: "RATE_LIMIT_EXCEEDED" } ] } },
                      status: 403))
      .then.to_return(json(messages: []))

    client.message_ids("x")

    expect(sleeps).to eq([ 2 ])
  end

  describe "rate limiting" do
    it "spaces requests at least 1/requests_per_second apart" do
      now = 100.0
      waits = []
      throttled = described_class.new(service: service, requests_per_second: 4, clock: -> { now },
                                      sleeper: ->(s) { waits << s.round(3); now += s })
      stub_request(:get, %r{/users/me/messages/m\d}).to_return(json(id: "m", threadId: "t"))

      3.times { |i| throttled.message("m#{i}") }

      expect(waits).to eq([ 0.25, 0.25 ]) # first request immediately, then 250ms apart
    end

    it "doesn't wait when requests are already slower than the limit" do
      now = 100.0
      waits = []
      throttled = described_class.new(service: service, requests_per_second: 4, clock: -> { now += 1.0 },
                                      sleeper: ->(s) { waits << s })
      stub_request(:get, %r{/users/me/messages/m\d}).to_return(json(id: "m", threadId: "t"))

      3.times { |i| throttled.message("m#{i}") }

      expect(waits).to be_empty
    end
  end

  it "gives up after max_retries" do
    stub_request(:get, list_url).to_return(json({ error: { code: 500, message: "boom" } }, status: 500))

    expect { client.message_ids("x") }.to raise_error(described_class::Unavailable, /after 3 retries/)
  end

  it "raises AuthExpired on 401 so the UI can offer Reconnect Gmail" do
    stub_request(:get, list_url).to_return(json({ error: { code: 401, message: "Invalid Credentials" } }, status: 401))

    expect { client.message_ids("x") }.to raise_error(Tracker::Gmail::AuthExpired)
  end

  it "does not retry other client errors" do
    stub_request(:get, list_url).to_return(json({ error: { code: 400, message: "Invalid query" } }, status: 400))

    expect { client.message_ids("x") }.to raise_error(Google::Apis::ClientError)
    expect(sleeps).to be_empty
  end
end
