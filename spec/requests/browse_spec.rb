require "rails_helper"

RSpec.describe "Pages", type: :request do
  let!(:application) do
    ingest(
      create_email(category: "applied", subject: "Thanks for applying", thread_id: "t1", sent_at: 10.days.ago),
      create_email(category: "interview_scheduled", subject: "Interview invite", thread_id: "t2",
                   sent_at: 5.days.ago, scheduled_at: 3.days.from_now),
      create_email(category: "interview_scheduled", subject: "RE: Interview invite", thread_id: "t2",
                   sent_at: 4.days.ago, is_reschedule: true, scheduled_at: 4.days.from_now)
    ).first
  end

  describe "dashboard" do
    it "shows stats, funnel, charts and upcoming interviews" do
      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Funnel", "Response rate", "Coming up", "Applications and rejections")
    end

    it "shows two roles at one company as separate lines, each with its own status and dates" do
      ingest(
        create_email(category: "applied", extracted_company: "Lakeshore", extracted_role: "Data Analyst",
                     thread_id: "l1", sent_at: Time.zone.parse("2026-08-24 10:00")),
        create_email(category: "rejection", extracted_company: "Lakeshore", extracted_role: "Data Analyst",
                     thread_id: "l2", sent_at: Time.zone.parse("2026-08-29 10:00")),
        create_email(category: "applied", extracted_company: "Lakeshore", extracted_role: "Analytics Engineer",
                     thread_id: "l3", sent_at: 3.days.ago)
      )

      get root_path

      section = response.body[/By company.*?By source/m]
      expect(section).to include("2 applications", "Data Analyst", "Analytics Engineer", "Rejected", "Awaiting reply",
                                 "24 Aug", "29 Aug")
      expect(section).not_to include("Rejected, Awaiting reply") # no merged, ambiguous outcome
    end

    it "shows an empty state with no data" do
      Application.destroy_all
      get root_path

      expect(response.body).to include("No applications yet")
    end
  end

  describe "applications" do
    it "lists and filters, rendering the results frame" do
      get applications_path(q: "acme", outcome: "in_progress", range: "30", sort: "company", dir: "asc")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="applications_results"', "Acme", "1 application matching")
    end

    it "shows the timeline with reschedules under their round and links to emails" do
      get application_path(application)

      expect(response.body).to include("Round 1", "Rescheduled", "Interview invite")
    end

    it "shows a source email" do
      get email_path(application.emails.first)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "manual add" do
    it "creates an application with an applied event" do
      post applications_path, params: { application: { company_name: "Initech Pvt Ltd", role: "SRE", source: "referral",
                                                       applied_on: 3.days.ago.to_date.iso8601, notes: "via Sam" } }

      created = Application.find_by!(company_key: "initech")
      expect(response).to redirect_to(application_path(created))
      expect(created).to have_attributes(manual: true, source: "referral", derived_status: "applied")
      expect(created.events.map(&:kind)).to eq([ "applied" ])
    end

    it "re-renders with an error when the company is missing" do
      post applications_path, params: { application: { company_name: " ", role: "SRE" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Company name can")
    end
  end

  describe "review queue" do
    let!(:unsure) do
      create_email(category: "rejection", extracted_company: "Acme", needs_review: true, confidence: 0.5,
                   subject: "Thank you for your interest", thread_id: "t9", sent_at: 1.day.ago)
    end

    it "shows the next email to review" do
      get reviews_path

      expect(response.body).to include("Thank you for your interest", "1 email left")
    end

    it "confirming a category re-runs inference" do
      patch review_path(unsure), params: { category: "rejection", company: "Acme" }

      expect(response).to redirect_to(reviews_path)
      expect(application.reload.derived_status).to eq("rejection")
      expect(unsure.reload.review_state).to eq("confirmed")
    end

    it "discarding keeps it out of every count" do
      patch review_path(unsure), params: { discard: "1" }

      expect(unsure.reload.review_state).to eq("discarded")
      expect(Email.review_queue).to be_empty
      expect(application.reload.derived_status).to eq("interview_scheduled")
    end
  end

  describe "sync" do
    it "shows the form, the Gmail status and explains it fetches new mail" do
      allow(Tracker::Gmail::Auth).to receive(:status).and_return(:expired)

      get sync_path

      expect(response.body).to include("Reconnect Gmail", "Sync new mail", "Fetches <strong>new</strong> mail")
      expect(response.body).to include(%(value="#{(Date.current - 60).iso8601}"))
    end

    it "starts a background sync for the chosen range" do
      allow(Tracker::Sync).to receive(:start)

      post sync_path, params: { date_from: "2026-07-01", date_to: "2026-08-31" }

      expect(Tracker::Sync).to have_received(:start).with(date_from: Date.new(2026, 7, 1), date_to: Date.new(2026, 8, 31))
      expect(response).to redirect_to(sync_path)
    end

    it "disables the button while a sync is running" do
      SyncRun.create!(started_at: Time.current, state: "running", date_from: Date.current, date_to: Date.current)
      TRACKER_SYNC_THREAD.set(Thread.new { sleep 0.5 })

      get sync_path

      expect(response.body).to include("Syncing…")
      expect(response.body).to match(/<input[^>]*disabled[^>]*value="Syncing…"|value="Syncing…"[^>]*disabled/)
    ensure
      TRACKER_SYNC_THREAD.set(nil)
    end

    it "rejects an inverted range" do
      post sync_path, params: { date_from: "2026-08-31", date_to: "2026-07-01" }

      expect(flash[:alert]).to include("start date")
    end
  end
end
