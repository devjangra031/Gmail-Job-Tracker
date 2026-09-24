# Classifies emails whose format is fixed and whose type is known for certain,
# without calling the LLM (no tokens):
#
# LinkedIn names each email's type in its tracking links, and these have formulaic subjects:
#   application_confirmation*   "Yogesh, your application was sent to Hire Feed"
#                               body: "Your application was sent to Hire Feed <Role> Hire Feed <Location> ..."
#   jobs_application_rejected   "Your application to Ruby on Rails Developer at Vastika Inc"
#   jobs_job_application_viewed "Your application was viewed by RxMen"
# Cutshort (notify@cutshort.io):
#   "Your application for job <Role> was shortlisted by <Person> from <Company>"
#
# Anything that doesn't match exactly returns nil and goes to the LLM as usual —
# including Cutshort recruiter messages, whose meaning depends on what they say.
module Tracker
  module RuleClassifier
    CUTSHORT_SHORTLISTED = /\AYour application for job (.+?) was shortlisted by .+? from (.+)\z/i

    module_function

    def call(email)
      subject = Classifier::Cleaner.text(email.subject)
      cutshort(email, subject) || linkedin(email, subject)
    end

    def cutshort(email, subject)
      sender = (email.from_address.to_s[/<([^>]+)>/, 1] || email.from_address).to_s.strip.downcase
      return unless sender.end_with?("@cutshort.io", ".cutshort.io")

      role, company = subject.match(CUTSHORT_SHORTLISTED)&.captures
      result("shortlisted", company, role, "Cutshort shortlist notification") if company
    end

    def linkedin(email, subject)
      reason = "LinkedIn #{email.linkedin_type.to_s.tr('_', ' ')}"

      case email.linkedin_type.to_s
      when /\Aapplication_confirmation/
        company = subject[/your application was sent to (.+)\z/i, 1]
        result("applied", company, confirmation_role(email.body, company), reason) if company
      when "jobs_application_rejected"
        role, company = subject.match(/\AYour application to (.+) at (.+)\z/i)&.captures
        result("rejection", company, role, reason) if company
      when "jobs_job_application_viewed"
        company = subject[/\AYour application was viewed by (.+)\z/i, 1]
        result("other", company, nil, reason) if company
      end
    end

    # "Your application was sent to <Company> <Role> <Company> <Location>": the role
    # sits between the two mentions of the company.
    def confirmation_role(body, company)
      text = Classifier::Cleaner.text(body)
      name = Regexp.escape(company)
      text[/Your application was sent to #{name}\s+(.+?)\s+#{name}\b/i, 1]&.truncate(160)
    end

    def result(category, company, role, reason)
      Classifier::Result.new(category: category, company: company.strip, role: role&.strip.presence,
                             round_label: nil, round_hint: nil, is_reschedule: false, scheduled_at: nil,
                             confidence: 0.99, model: "rule", tokens: 0, reason: reason, valid: true)
    end
  end
end
