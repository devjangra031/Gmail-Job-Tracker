require "rails_helper"

RSpec.describe Tracker::Analytics do
  let(:now) { Time.zone.parse("2026-09-23 12:00") }

  # Builds one application from (category, days_ago[, extra]) steps.
  def app(company, *steps)
    emails = steps.map do |category, days_ago, extra|
      create_email(category: category, extracted_company: company, sent_at: now - days_ago.days, **(extra || {}))
    end
    ingest(*emails).first
  end

  let!(:rejected) { app("Acme", [ "applied", 40 ], [ "rejection", 30 ]) }
  let!(:interviewing) { app("Globex", [ "applied", 20 ], [ "ai_screen", 18 ], [ "interview_scheduled", 10, { scheduled_at: now + 2.days } ]) }
  let!(:offered) { app("Initech", [ "applied", 60 ], [ "interview_scheduled", 50 ], [ "offer", 40 ]) }
  let!(:ghosted) { app("Hooli", [ "applied", 45 ]) }
  let!(:waiting) { app("Contoso", [ "applied", 5 ]) }

  subject(:analytics) { described_class.new(now: now) }

  it "counts the headline stats" do
    expect(analytics.stats).to eq(total: 5, awaiting: 1, in_progress: 1, ghosted: 1, rejected: 1, offers: 1)
  end

  it "builds the funnel by furthest stage reached, with drop-off" do
    funnel = analytics.funnel.to_h { |step| [ step[:stage], step.slice(:count, :drop_off) ] }

    expect(funnel).to eq(
      "applied" => { count: 5, drop_off: nil },
      "screened" => { count: 2, drop_off: 60.0 },     # Globex (AI screen) and Initech (interview implies past screening)
      "interviewed" => { count: 2, drop_off: 0.0 },
      "offer" => { count: 1, drop_off: 50.0 }
    )
  end

  it "computes response, rejection and ghost rates" do
    expect(analytics.rates).to eq(response: 60.0, rejection: 20.0, ghost: 20.0)
  end

  it "computes median / p90 days to first reply and median days to rejection" do
    # First replies: Acme 10d, Globex 2d, Initech 10d.
    expect(analytics.timings).to include(median_first_response: 10.0, p90_first_response: 10.0,
                                         median_rejection: 10.0, responses_measured: 3)
  end

  it "groups applications and rejections per month in Ruby, filling empty buckets" do
    monthly = analytics.over_time(:month)

    expect(monthly[:applications]).to eq(Date.new(2026, 7, 1) => 1, Date.new(2026, 8, 1) => 2, Date.new(2026, 9, 1) => 2)
    expect(monthly[:rejections]).to eq(Date.new(2026, 7, 1) => 0, Date.new(2026, 8, 1) => 1, Date.new(2026, 9, 1) => 0)
  end

  it "groups per week starting Monday" do
    weekly = analytics.over_time(:week)

    expect(weekly[:applications].keys).to all(satisfy(&:monday?))
    expect(weekly[:applications].values.sum).to eq(5)
  end

  it "summarises per company and per source" do
    expect(analytics.per_company.find { |r| r[:company] == "Initech" }).to include(furthest_stage: "offer", outcome: "Offer")
    expect(analytics.per_source).to eq([ { source: "direct", applications: 5, responded: 3, response_rate: 60.0 } ])
  end

  it "lists upcoming interviews in the pipeline" do
    expect(analytics.pipeline.map { |row| [ row[:application], row[:round] ] }).to eq([ [ interviewing, 2 ] ])
  end
end
