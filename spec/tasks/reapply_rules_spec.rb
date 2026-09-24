require "rails_helper"
require "rake"

RSpec.describe "tracker:reapply_rules" do
  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.empty? }

  def run_task
    Rake::Task["tracker:reapply_rules"].reenable
    expect { Rake::Task["tracker:reapply_rules"].invoke }.to output(/Updated/).to_stdout
  end

  let!(:applied) do
    create_email(category: "applied", extracted_company: "Incubyte", extracted_role: "Software Craftsperson/ROR- Staff",
                 thread_id: "a", sent_at: 20.days.ago)
  end
  let!(:shortlist) do
    # What the LLM stored before the "shortlisted" stage existed.
    create_email(category: "other", extracted_company: "Incubyte", thread_id: "b", sent_at: 10.days.ago,
                 from_address: "Cutshort Team <notify@cutshort.io>",
                 subject: "Your application for job Software Craftsperson/ROR- Staff was shortlisted by Sandli Srivastava from Incubyte")
  end

  it "upgrades old classifications with the local rules, without calling Groq, and updates the application" do
    ingest(applied, shortlist)

    run_task

    expect(shortlist.reload).to have_attributes(category: "shortlisted", classifier_model: "rule")
    application = shortlist.application
    expect(application.outcome).to eq("in_progress")
    expect(application.journey.map(&:label)).to eq(%w[Applied Shortlisted])
    expect(a_request(:any, /groq/)).not_to have_been_made
  end

  it "never overrides a decision made in the review queue" do
    shortlist.update!(review_state: "confirmed")

    run_task

    expect(shortlist.reload.category).to eq("other")
  end
end
