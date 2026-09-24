# Recognises job suggestions (not applications) without calling the LLM, so they
# cost no tokens: "X is hiring", "jobs similar to", saved-job reminders, alert
# senders. Deliberately narrow — anything it misses still goes to the classifier,
# which labels it job_alert.
module Tracker
  module NoiseFilter
    # LinkedIn email types (from tracking links) that are recommendations/reminders,
    # or an application that never went through (offsite_application_failure).
    LINKEDIN_NOISE_TYPE = /reminder|suggestion|recommend|alert|digest|qualification_board|application_failure/

    module_function

    # Returns a short reason when the email is a suggestion, else nil.
    def job_alert_reason(from:, subject:, body:, linkedin_type: nil)
      address = (from.to_s[/<([^>]+)>/, 1] || from).to_s.strip.downcase
      return "alert sender #{address}" if Tracker.config[:noise_senders].include?(address)

      type = linkedin_type || Classifier::Cleaner.linkedin_type(body)
      return "LinkedIn #{type}" if type&.match?(LINKEDIN_NOISE_TYPE)

      subject_text = subject.to_s.downcase.tr("’", "'")
      phrase = Tracker.config[:noise_subject_phrases].find { |p| subject_text.include?(p.downcase) }
      "subject contains \"#{phrase}\"" if phrase
    end

    def job_alert?(email)
      job_alert_reason(from: email.from_address, subject: email.subject, body: email.body,
                       linkedin_type: email.linkedin_type).present?
    end
  end
end
