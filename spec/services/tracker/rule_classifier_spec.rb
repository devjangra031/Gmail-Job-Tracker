require "rails_helper"

RSpec.describe Tracker::RuleClassifier do
  def email(subject, type, body: "")
    build_email(subject: subject, linkedin_type: type, body: body, category: nil)
  end

  it "reads company and role from a LinkedIn application confirmation" do
    result = described_class.call(email(
      "Yogesh, your application was sent to Hire Feed", "application_confirmation_with_nba",
      body: "Your application was sent to Hire Feed Senior Backend Software Engineer (Remote) Hire Feed India View job: ---"
    ))

    expect(result).to have_attributes(category: "applied", company: "Hire Feed", valid: true, model: "rule", tokens: 0,
                                      role: "Senior Backend Software Engineer (Remote)")
  end

  it "handles company names with punctuation" do
    result = described_class.call(email(
      "Yogesh, your application was sent to Disha: AI Health Coach", "application_confirmation_with_nba",
      body: "Your application was sent to Disha: AI Health Coach Senior Software Engineer Disha: AI Health Coach Gurugram"
    ))

    expect(result).to have_attributes(company: "Disha: AI Health Coach", role: "Senior Software Engineer")
  end

  it "still classifies a confirmation when the role can't be read" do
    result = described_class.call(email("Yogesh, your application was sent to Leena AI", "application_confirmation", body: ""))

    expect(result).to have_attributes(category: "applied", company: "Leena AI", role: nil)
  end

  it "reads role and company from a LinkedIn rejection, splitting on the last ' at '" do
    result = described_class.call(email("Your application to Technical Lead at Scale at Cog Culture", "jobs_application_rejected"))

    expect(result).to have_attributes(category: "rejection", company: "Cog Culture", role: "Technical Lead at Scale")
  end

  it "reads the company from 'application viewed'" do
    expect(described_class.call(email("Your application was viewed by RxMen", "jobs_job_application_viewed")))
      .to have_attributes(category: "other", company: "RxMen")
  end

  describe "Cutshort" do
    def cutshort(subject)
      build_email(subject: subject, from_address: "Cutshort Team <notify@cutshort.io>", category: nil)
    end

    it "reads a shortlist notification: role, and the company after 'from'" do
      result = described_class.call(cutshort(
        "Your application for job Software Craftsperson/ROR- Staff was shortlisted by Sandli Srivastava from Incubyte"
      ))

      expect(result).to have_attributes(category: "shortlisted", company: "Incubyte",
                                        role: "Software Craftsperson/ROR- Staff", model: "rule")
    end

    it "leaves recruiter messages to the LLM, which reads what they say" do
      expect(described_class.call(cutshort("Neha from Quanta sent you a message"))).to be_nil
    end

    it "ignores the same wording from anyone but Cutshort" do
      email = build_email(subject: "Your application for job X was shortlisted by Y from Z",
                          from_address: "someone@example.com", category: nil)

      expect(described_class.call(email)).to be_nil
    end
  end

  it "leaves anything else to the LLM" do
    expect(described_class.call(email("Interview invitation", nil))).to be_nil
    expect(described_class.call(email("Something unexpected", "jobs_application_rejected"))).to be_nil
  end
end
