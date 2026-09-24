require "rails_helper"

RSpec.describe Tracker::Classifier::Prompt do
  def input(**attrs)
    Tracker::Classifier::Input.new(**{
      from: "LinkedIn <jobs-noreply@linkedin.com>", subject: "Alex, your application was sent to Brightwave",
      sent_at: Time.zone.parse("2026-09-22 10:58"), body: "Body text " * 30, snippet: "Snippet", outgoing: false
    }.merge(attrs))
  end

  it "mentions JSON in the system prompt (Groq JSON mode requires it) and the time zone" do
    system = described_class.system

    expect(system).to include("JSON", "Asia/Kolkata", "+05:30")
  end

  it "strips URLs and invisible padding from the body" do
    body = "Your application was sent to Brightwave͏͏ View job: https://www.linkedin.com/comm/jobs/view/123?x=1 " \
           "Need help?<https://aka.ms/Join> ----------------- Applied on September 22"

    message = described_class.user_message(input(body: body))

    expect(message).to include("Body: Your application was sent to Brightwave View job: Need help? | Applied on September 22")
    expect(message).not_to include("http", "͏")
  end

  it "surfaces LinkedIn's email type from the tracking links" do
    body = "Your update from Tessellate https://www.linkedin.com/help?lipi=urn%3Ali%3Apage%3Aemail_email_jobs_application_rejected_01%3BHK5r"

    expect(described_class.user_message(input(body: body))).to include("LinkedIn email type: jobs_application_rejected")
  end

  it "adds the snippet when the plain-text body is nearly empty" do
    message = described_class.user_message(input(body: "Please Enable HTML", snippet: "Application Confirmed. Applied Position X"))

    expect(message).to include("Snippet: Application Confirmed. Applied Position X")
  end

  it "marks outgoing mail and includes the local date and weekday" do
    message = described_class.user_message(input(outgoing: true))

    expect(message).to include("Direction: outgoing", "Date: 2026-09-22T10:58:00+05:30 (Tuesday)")
  end

  it "caps the body at 1500 characters" do
    message = described_class.user_message(input(body: "word " * 1000))

    expect(message[/Body: (.*)/m, 1].length).to be <= 1500
  end
end
