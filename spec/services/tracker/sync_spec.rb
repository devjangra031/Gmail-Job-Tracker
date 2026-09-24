require "rails_helper"

RSpec.describe Tracker::Sync do
  # Stands in for Tracker::Gmail::Client: returns canned messages, no network.
  class FakeGmail
    attr_reader :queries, :fetched

    def initialize(messages, fail_with: nil)
      @messages = messages.index_by(&:id)
      @fail_with = fail_with
      @queries = []
      @fetched = []
    end

    def message_ids(query)
      raise @fail_with if @fail_with

      @queries << query
      @messages.keys
    end

    def message(id)
      @fetched << id
      @messages.fetch(id)
    end
  end

  def gmail_message(id, subject:, body:, from: "Brightwave <no-reply@hire.lever.co>", thread: id, at: 1.day.ago)
    part = Google::Apis::GmailV1::MessagePart.new(
      mime_type: "text/plain", filename: "",
      headers: [ Google::Apis::GmailV1::MessagePartHeader.new(name: "From", value: from),
                 Google::Apis::GmailV1::MessagePartHeader.new(name: "Subject", value: subject) ],
      body: Google::Apis::GmailV1::MessagePartBody.new(data: body)
    )
    Google::Apis::GmailV1::Message.new(id: id, thread_id: thread, label_ids: [ "INBOX" ], snippet: body.first(50),
                                       internal_date: at.to_i * 1000, payload: part)
  end

  let(:run) { SyncRun.create!(started_at: Time.current, date_from: 60.days.ago.to_date, date_to: Date.current) }
  let(:classifier) { Tracker::Classifier.new(provider: groq_provider) }
  let(:messages) do
    [
      gmail_message("g1", subject: "Thank you for applying to Brightwave", at: 3.days.ago,
                          body: "Thanks for applying for Backend Engineer at Brightwave Labs. We will review it."),
      gmail_message("g2", subject: "Lumen Pay is hiring - be an early applicant!", at: 5.days.ago,
                          from: "Naukri Alerts <naukrialerts@naukri.com>", body: "Freshly posted opportunity for you.")
    ]
  end

  def perform(gmail)
    described_class.new(run, gmail: gmail, classifier: classifier, sleeper: ->(_) { }).call
    run.reload
  end

  it "fetches only new mail for the date range, classifies it, and finishes" do
    stub_request(:post, groq_chat_url).to_return(groq_reply(classification(company: "Brightwave Labs")))
    create_email(gmail_message_id: "already-here", classified_at: Time.current)
    gmail = FakeGmail.new(messages + [ gmail_message("already-here", subject: "old", body: "old mail body text here") ])

    perform(gmail)

    expect(gmail.queries.first).to include("after:#{60.days.ago.to_date.in_time_zone.beginning_of_day.to_i}")
    expect(gmail.fetched).to contain_exactly("g1", "g2")
    expect(run).to have_attributes(state: "done", phase: "classifying", emails_found: 3, emails_new: 2,
                                   emails_fetched: 2, emails_to_classify: 2, emails_classified: 2, errors_count: 0)
    expect(a_request(:post, groq_chat_url)).to have_been_made.once # the job suggestion never reaches Groq
    expect(Application.find_by(company_key: "brightwave labs")).to be_present
    expect(Email.find_by(gmail_message_id: "g2")).to have_attributes(category: "job_alert", application_id: nil)
  end

  it "stops cleanly on a Groq daily limit and resumes on the next sync" do
    stub_request(:post, groq_chat_url).to_return(groq_error(429, message: "Limit reached: tokens per day (TPD)"))
    more = messages + [ gmail_message("g3", subject: "Interview invitation", body: "We'd like to invite you to interview.") ]

    perform(FakeGmail.new(more))

    expect(run.state).to eq("failed")
    expect(run.last_error).to include("tokens per day", "sync again later")
    expect(Email.where(gmail_message_id: %w[g1 g2 g3]).count).to eq(3) # everything fetched is kept
    expect(Email.find_by(gmail_message_id: "g2").classified_at).to be_present # suggestion done locally
    expect(Email.unclassified.count).to eq(2)

    WebMock.reset!
    stub_request(:post, groq_chat_url).to_return(groq_reply(classification))
    next_run = SyncRun.create!(started_at: Time.current, date_from: run.date_from, date_to: run.date_to)
    described_class.new(next_run, gmail: FakeGmail.new(more), classifier: classifier, sleeper: ->(_) { }).call

    expect(next_run.reload).to have_attributes(state: "done", emails_new: 0, emails_to_classify: 2)
    expect(Email.unclassified.count).to eq(0)
  end

  it "marks Gmail as needing reconnection when the token is rejected" do
    allow(Tracker::Gmail::Auth).to receive(:mark_expired!)

    perform(FakeGmail.new([], fail_with: Tracker::Gmail::AuthExpired.new("invalid_grant")))

    expect(run.state).to eq("failed")
    expect(run.last_error).to include("Reconnect Gmail")
    expect(Tracker::Gmail::Auth).to have_received(:mark_expired!)
  end

  it "says 'not connected' (not 'expired') when Gmail was never connected" do
    allow(Tracker::Gmail::Auth).to receive(:status).and_return(:disconnected)
    allow(Tracker::Gmail::Auth).to receive(:mark_expired!)

    perform(FakeGmail.new([], fail_with: Tracker::Gmail::AuthExpired.new("Gmail is not connected.")))

    expect(run.last_error).to include("isn't connected")
    expect(Tracker::Gmail::Auth).not_to have_received(:mark_expired!)
  end

  it "fails with a readable message when the Groq key is missing, keeping fetched mail" do
    allow(Tracker::Providers).to receive(:default).and_raise(Tracker::Providers::StopRun, "GROQ_API_KEY is not set.")

    described_class.new(run, gmail: FakeGmail.new(messages), sleeper: ->(_) { }).call

    expect(run.reload).to have_attributes(state: "failed", last_error: "GROQ_API_KEY is not set.")
    expect(Email.where(gmail_message_id: %w[g1 g2]).count).to eq(2)
  end

  it "counts a message that can't be read as an error and carries on" do
    stub_request(:post, groq_chat_url).to_return(groq_reply(classification))
    gmail = FakeGmail.new(messages)
    allow(gmail).to receive(:message).and_call_original
    allow(gmail).to receive(:message).with("g1").and_raise(StandardError, "garbled MIME")

    perform(gmail)

    expect(run).to have_attributes(state: "done", errors_count: 1, emails_fetched: 2)
    expect(run.last_error).to include("garbled MIME")
  end

  describe ".start" do
    it "refuses to start while another sync is running" do
      SyncRun.create!(started_at: Time.current, state: "running")
      TRACKER_SYNC_THREAD.set(Thread.new { sleep 0.5 })

      expect { described_class.start(date_from: Date.current, date_to: Date.current, async: false) }
        .to raise_error(described_class::AlreadyRunning)
    ensure
      TRACKER_SYNC_THREAD.set(nil)
    end

    it "marks a 'running' sync with no live thread as interrupted" do
      stale = SyncRun.create!(started_at: 1.hour.ago, state: "running")
      TRACKER_SYNC_THREAD.set(nil)

      expect(described_class.running?).to be(false)
      expect(stale.reload).to have_attributes(state: "failed")
      expect(stale.last_error).to include("Interrupted")
    end
  end
end
