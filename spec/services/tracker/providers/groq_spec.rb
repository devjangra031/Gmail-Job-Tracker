require "rails_helper"

RSpec.describe Tracker::Providers::Groq do
  let(:sleeps) { [] }
  let(:provider) { groq_provider(sleeps) }

  def complete
    provider.complete(system: "Reply in JSON.", messages: [ { role: "user", content: "hi" } ])
  end

  it "posts to Groq (never OpenAI) with JSON mode, temperature 0 and the configured model" do
    stub = stub_request(:post, groq_chat_url)
      .with(headers: { "Authorization" => "Bearer test-key" }) do |request|
        body = JSON.parse(request.body)
        body["model"] == "test-model" && body["temperature"] == 0 &&
          body["response_format"] == { "type" => "json_object" } &&
          body["messages"].first == { "role" => "system", "content" => "Reply in JSON." } &&
          !body.key?("reasoning_effort")
      end
      .to_return(groq_reply({ ok: true }, tokens: 42))

    completion = complete

    expect(stub).to have_been_requested
    expect(completion).to have_attributes(text: '{"ok":true}', tokens: 42)
    expect(a_request(:any, /openai\.com/)).not_to have_been_made
  end

  it "sends reasoning_effort when configured" do
    stub = stub_request(:post, groq_chat_url)
      .with { |request| JSON.parse(request.body)["reasoning_effort"] == "low" }
      .to_return(groq_reply({}))

    groq_provider(reasoning_effort: "low").complete(system: "JSON", messages: [])

    expect(stub).to have_been_requested
  end

  it "fails fast without an API key" do
    expect { described_class.new(api_key: "") }.to raise_error(Tracker::Providers::StopRun, /GROQ_API_KEY/)
  end

  describe "rate limits" do
    it "honours retry-after on 429, then succeeds" do
      stub_request(:post, groq_chat_url)
        .to_return(groq_error(429, message: "Rate limit reached on tokens per minute (TPM)", headers: { "retry-after" => "3" }))
        .then.to_return(groq_reply({ ok: 1 }))

      expect(complete.text).to eq('{"ok":1}')
      expect(sleeps).to eq([ 3.0 ])
    end

    it "backs off exponentially when there is no retry-after" do
      stub_request(:post, groq_chat_url)
        .to_return(groq_error(429, message: "slow down")).times(2)
        .then.to_return(groq_reply({}))

      complete

      expect(sleeps).to eq([ 2, 4 ])
    end

    it "stops immediately on a daily limit without sleeping" do
      stub_request(:post, groq_chat_url)
        .to_return(groq_error(429, message: "Rate limit reached for model on tokens per day (TPD): Limit 200000",
                                   headers: { "retry-after" => "30" }))

      expect { complete }.to raise_error(Tracker::Providers::RateLimited, /tokens per day/)
      expect(sleeps).to be_empty
    end

    it "stops instead of waiting when retry-after is longer than the configured maximum" do
      stub_request(:post, groq_chat_url)
        .to_return(groq_error(429, message: "Please try again in 7m", headers: { "retry-after" => "420" }))

      expect { complete }.to raise_error(Tracker::Providers::RateLimited)
      expect(sleeps).to be_empty
    end

    it "gives up after max_retries" do
      stub_request(:post, groq_chat_url).to_return(groq_error(429, message: "busy", headers: { "retry-after" => "1" }))

      expect { complete }.to raise_error(Tracker::Providers::RateLimited, /after 3 retries/)
      expect(sleeps).to eq([ 1.0, 1.0, 1.0 ])
    end
  end

  it "retries 5xx with backoff" do
    stub_request(:post, groq_chat_url)
      .to_return(status: 503, body: "unavailable")
      .then.to_return(groq_reply({}))

    complete

    expect(sleeps).to eq([ 2 ])
  end

  it "raises RequestFailed when 5xx persists" do
    stub_request(:post, groq_chat_url).to_return(status: 500, body: "boom")

    expect { complete }.to raise_error(Tracker::Providers::RequestFailed)
  end

  it "reports Groq's json_validate_failed as invalid output" do
    stub_request(:post, groq_chat_url)
      .to_return(groq_error(400, message: "Failed to generate JSON", code: "json_validate_failed"))

    expect { complete }.to raise_error(Tracker::Providers::InvalidOutput)
  end

  it "stops the run with a pointer to tracker:models when the model is retired" do
    stub_request(:post, groq_chat_url)
      .to_return(groq_error(400, message: "The model has been decommissioned", code: "model_decommissioned"))

    expect { complete }.to raise_error(Tracker::Providers::StopRun, /tracker:models/)
  end

  it "stops the run on a bad key without echoing it" do
    stub_request(:post, groq_chat_url).to_return(groq_error(401, message: "Invalid API Key"))

    expect { complete }.to raise_error(Tracker::Providers::StopRun) { |e| expect(e.message).not_to include("test-key") }
  end

  it "lists models from GET /models" do
    stub_request(:get, "https://api.groq.com/openai/v1/models")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { data: [ { id: "qwen/qwen3-32b" }, { id: "openai/gpt-oss-20b" } ] }.to_json)

    expect(provider.models).to eq(%w[openai/gpt-oss-20b qwen/qwen3-32b])
  end
end
