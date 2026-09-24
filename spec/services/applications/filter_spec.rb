require "rails_helper"

RSpec.describe Applications::Filter do
  let(:now) { Time.current }

  def app(company, role: nil, source: "direct", applied_days_ago: 5, status: "applied", activity_days_ago: nil)
    Application.create!(company_name: company, company_key: company.downcase, role: role, source: source,
                        first_applied_at: now - applied_days_ago.days, derived_status: status,
                        last_activity_at: now - (activity_days_ago || applied_days_ago).days)
  end

  let!(:acme) { app("Acme", role: "Backend Engineer", source: "lever.co", applied_days_ago: 3) }
  let!(:globex) { app("Globex", role: "Data Engineer", applied_days_ago: 20, status: "interview_scheduled", activity_days_ago: 2) }
  let!(:initech) { app("Initech", role: "Backend Lead", applied_days_ago: 50, status: "rejection") }
  let!(:hooli) { app("Hooli", applied_days_ago: 80) } # ghosted

  def results(params)
    described_class.new(params, now: now).relation.to_a
  end

  it "searches company and role, case-insensitively" do
    expect(results(q: "backend")).to contain_exactly(acme, initech)
    expect(results(q: "GLOB")).to eq([ globex ])
  end

  it "filters by outcome" do
    expect(results(outcome: "awaiting")).to eq([ acme ])
    expect(results(outcome: "in_progress")).to eq([ globex ])
    expect(results(outcome: "ghosted")).to eq([ hooli ])
    expect(results(outcome: "rejection")).to eq([ initech ])
  end

  it "filters by source" do
    expect(results(source: "lever.co")).to eq([ acme ])
  end

  it "filters by applied-date presets and custom ranges" do
    expect(results(range: "7")).to eq([ acme ])
    expect(results(range: "30")).to contain_exactly(acme, globex)
    expect(results(range: "60")).to contain_exactly(acme, globex, initech)
    expect(results(range: "custom", from: (now - 25.days).to_date.iso8601, to: (now - 10.days).to_date.iso8601))
      .to eq([ globex ])
  end

  it "sorts by a whitelisted column, ignoring anything else" do
    expect(results(sort: "company", dir: "asc").map(&:company_name)).to eq(%w[Acme Globex Hooli Initech])
    expect(results(sort: "idle").first).to eq(hooli)
    expect(results(sort: "drop table").first).to eq(globex) # unknown column falls back to last activity, newest first
  end
end
