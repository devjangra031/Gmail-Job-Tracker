require "rails_helper"

RSpec.describe Tracker::NoiseFilter do
  def reason(from:, subject:, body: "")
    described_class.job_alert_reason(from: from, subject: subject, body: body)
  end

  it "recognises alert-only senders" do
    expect(reason(from: "Naukri Alerts <naukrialerts@naukri.com>", subject: "Jobs for you from Lumen"))
      .to include("naukrialerts@naukri.com")
  end

  it "recognises LinkedIn recommendation and reminder emails by their tracking type" do
    body = "Your saved job is still available https://www.linkedin.com/x?lipi=urn%3Ali%3Apage%3Aemail_email_jobs_saved_job_reminder_01%3Babc"

    expect(reason(from: "LinkedIn <jobs-noreply@linkedin.com>", subject: "Alex, apply to Brightwave", body: body))
      .to include("saved_job_reminder")
  end

  [
    "Lumen Pay is hiring - be an early applicant!",
    "New jobs similar to Backend Engineer (India) at Brightwave",
    "Alex, your job’s expiring on Sep 27: Engineering Manager at Quanta",
    "Orbit Careers took action on your profile"
  ].each do |subject|
    it("recognises the subject #{subject.inspect}") { expect(reason(from: "x@naukri.com", subject: subject)).to be_present }
  end

  [
    [ "LinkedIn <jobs-noreply@linkedin.com>", "Alex, your application was sent to Brightwave",
      "x?lipi=urn%3Ali%3Apage%3Aemail_email_application_confirmation_with_nba_01%3B" ],
    [ "LinkedIn <jobs-noreply@linkedin.com>", "Your application to Backend Engineer at Tessellate",
      "x?lipi=urn%3Ali%3Apage%3Aemail_email_jobs_application_rejected_01%3B" ],
    [ "Orbit Health <orbithealth@myworkday.com>", "Update on Your Application for the Engineering Manager role", "" ],
    [ "Neha <neha@kestrelsoft.com>", "L1 Interview | ALEX KUMAR | Backend Engineer(ROR)", "" ],
    [ "hr@quanta.com", "Your offer is expiring soon", "" ]
  ].each do |from, subject, body|
    it("leaves #{subject.inspect} for the classifier") { expect(reason(from: from, subject: subject, body: body)).to be_nil }
  end
end
