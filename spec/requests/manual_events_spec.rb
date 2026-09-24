require "rails_helper"

RSpec.describe "Adding updates by hand (call, WhatsApp, in person)", type: :request do
  let!(:application) do
    ingest(
      create_email(category: "applied", extracted_company: "Money Forward", thread_id: "a", sent_at: 12.days.ago),
      create_email(category: "interview_scheduled", extracted_company: "Money Forward", thread_id: "b",
                   sent_at: 6.days.ago, round_hint: 1, round_label: "Round 1")
    ).first
  end

  def add(**event)
    post application_events_path(application), params: { event: { occurred_on: 2.days.ago.to_date.iso8601 }.merge(event) }
  end

  it "records a rejection that came by phone, updating status and journey" do
    add(kind: "rejection", note: "Recruiter called")

    expect(response).to redirect_to(application_path(application))
    application.reload
    expect(application.derived_status).to eq("rejection")
    expect(application.journey.last).to have_attributes(kind: "rejection", manual: true, note: "Recruiter called")
    expect(application.journey.last.at.to_date).to eq(2.days.ago.to_date)

    follow_redirect!
    expect(response.body).to include("added by you", "Recruiter called", "Rejected")
  end

  it "records a second round arranged on WhatsApp as its own round" do
    add(kind: "interview_scheduled", round_label: "Round 2", scheduled_at: 3.days.from_now.strftime("%Y-%m-%dT%H:%M"))

    expect(application.reload.derived_round).to eq(2)
    expect(application.journey.map(&:label)).to eq([ "Applied", "Round 1", "Round 2" ])
  end

  it "rejects future dates and missing kinds with a message" do
    add(kind: "rejection", occurred_on: 2.days.from_now.to_date.iso8601)
    expect(flash[:alert]).to include("future")

    add(kind: "ghosted")
    expect(flash[:alert]).to include("Kind")
    expect(application.events.where(email_id: nil)).to be_empty
  end

  it "can remove a hand-added update, and never an email-backed one" do
    add(kind: "rejection")
    manual = application.events.find_by(email_id: nil)

    delete application_event_path(application, manual)
    expect(application.reload.derived_status).to eq("interview_scheduled")

    email_event = application.events.where.not(email_id: nil).first
    delete application_event_path(application, email_event)
    expect(response).to have_http_status(:not_found)
  end

  it "keeps hand-added updates through recompute and regroup" do
    add(kind: "rejection", note: "WhatsApp")

    Applications::Recompute.all
    expect(application.reload.derived_status).to eq("rejection")

    Applications::Recompute.regroup
    regrouped = Application.find_by!(company_key: "money forward")
    expect(regrouped.derived_status).to eq("rejection")
    expect(regrouped.events.find_by(email_id: nil).note).to eq("WhatsApp")
  end
end
