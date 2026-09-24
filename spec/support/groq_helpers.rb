module GroqHelpers
  def groq_chat_url
    "https://api.groq.com/openai/v1/chat/completions"
  end

  def groq_reply(content, tokens: 100)
    {
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: { choices: [ { message: { role: "assistant", content: content.is_a?(String) ? content : content.to_json } } ],
              usage: { total_tokens: tokens } }.to_json
    }
  end

  def groq_error(status, message:, code: nil, headers: {})
    {
      status: status,
      headers: { "Content-Type" => "application/json" }.merge(headers),
      body: { error: { message: message, type: "invalid_request_error", code: code } }.to_json
    }
  end

  def classification(**overrides)
    {
      category: "applied", company: "Brightwave Labs", role: "Backend Engineer", round_label: nil,
      round_hint: nil, is_reschedule: false, scheduled_at: nil, confidence: 0.95, reason: "confirmation"
    }.merge(overrides)
  end

  def groq_provider(sleeps = [], **options)
    Tracker::Providers::Groq.new(api_key: "test-key", model: "test-model", reasoning_effort: nil,
                                 max_retries: 3, max_wait: 120, sleeper: ->(s) { sleeps << s }, **options)
  end
end

RSpec.configure { |config| config.include GroqHelpers }
