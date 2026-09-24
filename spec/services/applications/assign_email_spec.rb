require "rails_helper"

RSpec.describe Applications::AssignEmail do
  it "groups by company_key and normalized role" do
    a = create_email(extracted_company: "Acme Inc.", extracted_role: "Backend Engineer", thread_id: "t1")
    b = create_email(extracted_company: "ACME", extracted_role: "backend engineer!", thread_id: "t2",
                     category: "rejection")
    c = create_email(extracted_company: "Acme", extracted_role: "Data Analyst", thread_id: "t3")

    apps = ingest(a, b, c)

    expect(apps.size).to eq(2)
    expect(a.reload.application).to eq(b.reload.application)
    expect(c.reload.application).not_to eq(a.application)
  end

  it "joins a role-less email to the company's most recently active application" do
    older = create_email(extracted_role: "Backend Engineer", sent_at: 10.days.ago)
    newer = create_email(extracted_role: "Data Analyst", sent_at: 2.days.ago)
    roleless = create_email(extracted_role: nil, category: "rejection", sent_at: 1.day.ago)

    ingest(older, newer, roleless)

    expect(roleless.reload.application).to eq(newer.reload.application)
  end

  it "lets a role-less application adopt the first role it sees" do
    first = create_email(extracted_role: nil)
    second = create_email(extracted_role: "Platform Engineer", category: "interview_scheduled")

    application, = ingest(first, second)

    expect(application).to have_attributes(role: "Platform Engineer", role_key: "platform engineer")
    expect(Application.count).to eq(1)
  end

  it "always joins emails in the same thread, even if the company is extracted differently" do
    a = create_email(extracted_company: "Acme", thread_id: "shared")
    b = create_email(extracted_company: "Totally Different Co", thread_id: "shared", category: "rejection")

    ingest(a, b)

    expect(b.reload.application).to eq(a.reload.application)
    expect(Application.count).to eq(1)
  end

  it "falls back to the sender domain when the company is null" do
    email = create_email(extracted_company: nil, from_address: "Talent <talent@careers.globex.com>")

    application, = ingest(email)

    expect(application).to have_attributes(company_key: "globex", company_name: "Globex", source: "direct")
  end

  it "records the ATS domain as the source" do
    email = create_email(from_address: "Acme <no-reply@us.greenhouse-mail.io>")

    expect(ingest(email).first.source).to eq("greenhouse-mail.io")
  end

  it "leaves an email unassigned when neither company nor a usable domain is known" do
    email = create_email(extracted_company: nil, from_address: "no-reply@hire.lever.co")

    expect(ingest(email)).to be_empty
    expect(Application.count).to eq(0)
  end

  it "never creates an application from a job alert" do
    email = create_email(category: "job_alert", from_address: "jobs-noreply@linkedin.com")

    expect(ingest(email)).to be_empty
    expect(Application.count).to eq(0)
  end

  it "adopts an earlier orphan once its application appears (mail arrives newest-first)" do
    viewed = create_email(category: "other", extracted_company: "Novamed", thread_id: "viewed",
                          sent_at: 1.day.ago)
    expect(ingest(viewed)).to be_empty

    applied = create_email(category: "applied", extracted_company: "Novamed", thread_id: "applied",
                           sent_at: 2.days.ago)
    application, = ingest(applied)

    expect(viewed.reload.application).to eq(application)
    expect(application.events.map(&:kind)).to eq(%w[applied other])
  end

  it "lets 'other' attach to an existing application but never create one" do
    lone = create_email(category: "other", extracted_company: "Initech")
    expect(ingest(lone)).to be_empty

    applied = create_email(extracted_company: "Globex", thread_id: "g1")
    other = create_email(category: "other", extracted_company: "Globex", thread_id: "g2")
    application, = ingest(applied, other)

    expect(application.events.map(&:kind)).to eq(%w[applied other])
  end
end
