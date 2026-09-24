require "rails_helper"
require "rake"

RSpec.describe "tracker:remove_demo_data" do
  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.empty? }

  def run_task
    Rake::Task["tracker:remove_demo_data"].reenable
    expect { Rake::Task["tracker:remove_demo_data"].invoke }.to output(/Removed/).to_stdout
  end

  it "removes demo emails and their applications, keeping real mail" do
    demo = create_email(gmail_message_id: "seed-1", extracted_company: "Acme Payments")
    real = create_email(gmail_message_id: "18c2f00real", extracted_company: "Azilen")
    ingest(demo, real)
    Application.create!(company_name: "Harborview", company_key: "harborview", source: "manual", manual: true,
                        notes: "Applied through a referral.")

    run_task

    expect(Email.pluck(:gmail_message_id)).to eq([ "18c2f00real" ])
    expect(Application.pluck(:company_key)).to eq([ "azilen" ])
  end

  it "refuses while a sync is running, without marking that sync as interrupted" do
    running = SyncRun.create!(started_at: Time.current, state: "running")

    expect { Rake::Task["tracker:remove_demo_data"].tap(&:reenable).invoke }.to raise_error(SystemExit)
    expect(running.reload.state).to eq("running")
  end
end
