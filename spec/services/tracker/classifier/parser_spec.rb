require "rails_helper"

RSpec.describe Tracker::Classifier::Parser do
  let(:valid) do
    {
      category: "interview_scheduled", company: "Kestrel Softech Pvt. Ltd.", role: "Backend Engineer(ROR)",
      round_label: "L1 Interview", round_hint: 1, is_reschedule: false,
      scheduled_at: "2026-03-11T22:00:00+05:30", confidence: 0.96, reason: "L1 interview confirmed"
    }
  end

  def parse(hash_or_text)
    described_class.parse(hash_or_text.is_a?(String) ? hash_or_text : hash_or_text.to_json)
  end

  it "accepts a valid response" do
    attributes, problem = parse(valid)

    expect(problem).to be_nil
    expect(attributes).to include(category: "interview_scheduled", round_hint: 1, confidence: 0.96,
                                  company: "Kestrel Softech Pvt. Ltd.")
    expect(attributes[:scheduled_at]).to eq(Time.utc(2026, 3, 11, 16, 30))
  end

  it "tolerates harmless formatting: code fences, numeric strings, 'null' strings, missing reschedule flag" do
    text = "```json\n#{valid.merge(round_hint: "2", company: "null", is_reschedule: nil).to_json}\n```"

    attributes, = parse(text)

    expect(attributes).to include(round_hint: 2, company: nil, is_reschedule: false)
  end

  it "accepts job_alert as a category" do
    expect(parse(valid.merge(category: "job_alert")).first[:category]).to eq("job_alert")
  end

  {
    "not JSON" => "Sure! Here is the classification: applied",
    "a JSON array" => "[1, 2]"
  }.each do |description, text|
    it("rejects #{description}") { expect(parse(text).first).to be_nil }
  end

  {
    "an unknown category" => { category: "ghosted" },
    "confidence above 1" => { confidence: 1.4 },
    "non-numeric confidence" => { confidence: "high" },
    "a fractional round hint" => { round_hint: 1.5 },
    "a non-boolean reschedule flag" => { is_reschedule: "maybe" },
    "an unparseable date" => { scheduled_at: "sometime next week" }
  }.each do |description, change|
    it "rejects #{description} and says why" do
      attributes, problem = parse(valid.merge(change))

      expect(attributes).to be_nil
      expect(problem).to be_present
    end
  end
end
