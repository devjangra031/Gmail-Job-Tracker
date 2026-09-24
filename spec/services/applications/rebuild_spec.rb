require "rails_helper"

RSpec.describe Applications::Rebuild do
  it "excludes low-confidence emails until a human confirms them" do
    applied = create_email(category: "applied")
    unsure = create_email(category: "rejection", needs_review: true, confidence: 0.4)

    application, = ingest(applied, unsure)
    expect(application.derived_status).to eq("applied")
    expect(unsure.reload.application).to be_nil

    unsure.update!(review_state: "confirmed")
    Applications::IngestEmail.call(unsure)

    expect(application.reload.derived_status).to eq("rejection")
  end

  it "drops a discarded email's event and destroys an application left empty" do
    email = create_email(category: "applied")
    application, = ingest(email)

    email.update!(review_state: "discarded")
    Applications::IngestEmail.call(email)

    expect(Application.exists?(application.id)).to be(false)
    expect(email.reload.application).to be_nil
  end

  it "keeps manual applications and their manual events" do
    application = Application.create!(company_name: "Initech", company_key: "initech", source: "manual", manual: true)
    application.events.create!(kind: "applied", occurred_at: 3.days.ago)

    described_class.call(application)

    expect(application.reload.events.map(&:kind)).to eq([ "applied" ])
    expect(application.derived_status).to eq("applied")
  end

  it "recompute fixes stale derived data" do
    application, = ingest(
      create_email(category: "applied"),
      create_email(category: "rejection")
    )
    application.update_columns(derived_status: "offer", derived_round: 9)
    application.events.update_all(round_number: 42)

    Applications::Recompute.all

    expect(application.reload).to have_attributes(derived_status: "rejection", derived_round: 0)
    expect(application.events.map(&:round_number)).to eq([ 0, nil ])
  end

  it "regroup rebuilds grouping from scratch and keeps manual applications" do
    manual = Application.create!(company_name: "Initech", company_key: "initech", source: "manual", manual: true)
    manual.events.create!(kind: "applied", occurred_at: 5.days.ago)
    ingest(create_email(extracted_company: "Acme"), create_email(extracted_company: "Globex"))

    Applications::Recompute.regroup

    expect(Application.pluck(:company_key)).to contain_exactly("initech", "acme", "globex")
  end
end
