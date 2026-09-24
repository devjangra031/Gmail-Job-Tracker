require "rails_helper"

RSpec.describe Tracker::ClassifyEmails do
  let(:sleeps) { [] }
  let(:classifier) { Tracker::Classifier.new(provider: groq_provider) }

  def unclassified_email(**attrs)
    create_email(category: nil, extracted_company: nil, confidence: nil, classified_at: nil, **attrs)
  end

  def run(emails)
    described_class.call(emails, classifier: classifier, delay: 1.5, sleeper: ->(s) { sleeps << s })
  end

  it "classifies sequentially with a delay, persisting and grouping each email" do
    stub_request(:post, groq_chat_url)
      .to_return(groq_reply(classification))
      .then.to_return(groq_reply(classification(category: "rejection")))
    first = unclassified_email(thread_id: "a")
    second = unclassified_email(thread_id: "b")

    summary = run([ first, second ])

    expect(summary).to have_attributes(classified: 2, errors: 0, stopped: false, tokens: 200)
    expect(sleeps).to eq([ 1.5 ])
    expect(first.reload).to have_attributes(category: "applied", classifier_model: "test-model", needs_review: false)
    expect(first.application).to eq(second.reload.application)
    expect(first.application.derived_status).to eq("rejection")
  end

  it "labels job suggestions locally without calling Groq or pausing" do
    alert = unclassified_email(from_address: "Naukri Alerts <naukrialerts@naukri.com>",
                               subject: "Lumen Pay is hiring - be an early applicant!")

    summary = run([ alert ])

    expect(a_request(:any, /groq/)).not_to have_been_made
    expect(sleeps).to be_empty
    expect(summary).to have_attributes(classified: 1, tokens: 0)
    expect(alert.reload).to have_attributes(category: "job_alert", classifier_model: "rule", application: nil)
  end

  it "puts low-confidence and invalid results in the review queue, excluded from applications" do
    stub_request(:post, groq_chat_url).to_return(groq_reply(classification(confidence: 0.4)))
    email = unclassified_email

    run([ email ])

    expect(email.reload).to have_attributes(needs_review: true, application: nil)
    expect(Email.review_queue).to include(email)
  end

  it "stops cleanly on a daily limit, keeps finished work, and resumes on the next run" do
    daily = groq_error(429, message: "Rate limit reached on requests per day (RPD)")
    stub_request(:post, groq_chat_url)
      .to_return(groq_reply(classification))
      .then.to_return(daily)
    emails = Array.new(3) { |i| unclassified_email(thread_id: "t#{i}") }

    summary = run(emails)

    expect(summary).to have_attributes(classified: 1, stopped: true)
    expect(summary.last_error).to include("requests per day")
    expect(emails.map { |e| e.reload.classified_at.present? }).to eq([ true, false, false ])
    expect(emails.first.application).to be_present

    WebMock.reset!
    stub_request(:post, groq_chat_url).to_return(groq_reply(classification))

    resumed = run(Email.unclassified.order(:id).to_a)

    expect(resumed).to have_attributes(classified: 2, stopped: false)
    expect(Email.unclassified.count).to eq(0)
  end

  it "counts a failed request as an error, leaves that email for next time, and carries on" do
    stub_request(:post, groq_chat_url)
      .to_return(status: 500, body: "boom").times(4)
      .then.to_return(groq_reply(classification))
    failing = unclassified_email(thread_id: "x", subject: "Flaky one")
    fine = unclassified_email(thread_id: "y")

    summary = run([ failing, fine ])

    expect(summary).to have_attributes(classified: 1, errors: 1, stopped: false)
    expect(summary.last_error).to include("Flaky one")
    expect(failing.reload.classified_at).to be_nil
    expect(fine.reload.classified_at).to be_present
  end
end
