require "rails_helper"

RSpec.describe Tracker::Classifier do
  let(:classifier) { described_class.new(provider: groq_provider) }
  let(:input) do
    Tracker::Classifier::Input.new(from: "Brightwave <no-reply@hire.lever.co>", subject: "Thanks for applying",
                                   sent_at: Time.current, body: "We received your application.",
                                   snippet: nil, outgoing: false)
  end

  it "returns a valid result" do
    stub_request(:post, groq_chat_url).to_return(groq_reply(classification, tokens: 250))

    result = classifier.classify(input)

    expect(result).to have_attributes(valid: true, category: "applied", company: "Brightwave Labs",
                                      model: "test-model", tokens: 250)
    expect(result.needs_review?).to be(false)
  end

  it "flags low confidence for review" do
    stub_request(:post, groq_chat_url).to_return(groq_reply(classification(confidence: 0.55)))

    expect(classifier.classify(input).needs_review?).to be(true)
  end

  it "retries once on invalid JSON, telling the model what was wrong" do
    stub = stub_request(:post, groq_chat_url)
      .to_return(groq_reply("definitely applied!"))
      .then.to_return(groq_reply(classification))

    result = classifier.classify(input)

    expect(result.valid).to be(true)
    expect(stub).to have_been_requested.twice
    expect(a_request(:post, groq_chat_url).with { |r| JSON.parse(r.body)["messages"].last["content"].include?("not valid JSON") })
      .to have_been_made
  end

  it "retries once when Groq itself rejects the JSON output" do
    stub_request(:post, groq_chat_url)
      .to_return(groq_error(400, message: "Failed to generate JSON", code: "json_validate_failed"))
      .then.to_return(groq_reply(classification))

    expect(classifier.classify(input).valid).to be(true)
  end

  it "gives up after the retry and marks the result for review" do
    stub = stub_request(:post, groq_chat_url).to_return(groq_reply(classification(category: "ghosted")))

    result = classifier.classify(input)

    expect(stub).to have_been_requested.twice
    expect(result).to have_attributes(valid: false, category: nil)
    expect(result.reason).to include("unknown category")
    expect(result.needs_review?).to be(true)
  end
end
