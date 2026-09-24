# Classifies emails one at a time, oldest first (free-tier friendly), saving and ingesting each
# as soon as it's done so nothing is lost if the run stops. Emails that fail stay
# unclassified and are picked up by the next run.
module Tracker
  class ClassifyEmails
    Summary = Data.define(:classified, :errors, :tokens, :stopped, :last_error)

    def self.call(...)
      new(...).call
    end

    def initialize(emails, classifier: Classifier.new, delay: Tracker.config[:groq_delay_seconds],
                   sleeper: ->(seconds) { sleep(seconds) }, on_progress: nil)
      # Oldest first, so applications exist before the replies that refer to them.
      @emails = emails.sort_by { |email| [ email.sent_at, email.id ] }
      @classifier = classifier
      @delay = delay.to_f
      @sleeper = sleeper
      @on_progress = on_progress
    end

    def call
      classified = errors = tokens = 0
      last_error = nil
      called_api = false

      @emails.each do |email|
        # Suggestions and formulaic notifications are handled locally: no tokens, no pause.
        if (local = self.class.local_result(email))
          self.class.apply(email, local)
          classified += 1
          @on_progress&.call(email:, classified:, errors:)
          next
        end

        @sleeper.call(@delay) if called_api && @delay.positive?
        called_api = true

        begin
          result = @classifier.classify(Classifier::Input.from_email(email))
          self.class.apply(email, result)
          classified += 1
          tokens += result.tokens.to_i
        rescue Providers::StopRun => e
          return Summary.new(classified:, errors:, tokens:, stopped: true, last_error: e.message)
        rescue Providers::Error => e
          errors += 1
          last_error = "#{email.subject.to_s.truncate(60)}: #{e.message}"
        end

        @on_progress&.call(email:, classified:, errors:)
      end

      Summary.new(classified:, errors:, tokens:, stopped: false, last_error:)
    end

    # The free, local verdict for an email: a job suggestion, a formulaic
    # notification a rule can read, or nil (needs the LLM).
    def self.local_result(email)
      reason = NoiseFilter.job_alert_reason(from: email.from_address, subject: email.subject,
                                            body: email.body, linkedin_type: email.linkedin_type)
      return job_alert_result(reason) if reason

      RuleClassifier.call(email)
    end

    def self.job_alert_result(reason)
      Classifier::Result.new(category: "job_alert", company: nil, role: nil, round_label: nil, round_hint: nil,
                             is_reschedule: false, scheduled_at: nil, confidence: 1.0, model: "rule",
                             tokens: 0, reason: "Job suggestion (#{reason})", valid: true)
    end

    def self.apply(email, result)
      email.update!(
        category: result.category,
        extracted_company: result.company,
        extracted_role: result.role,
        round_label: result.round_label,
        round_hint: result.round_hint,
        is_reschedule: result.is_reschedule,
        scheduled_at: result.scheduled_at,
        confidence: result.confidence,
        classifier_reason: result.reason,
        classifier_model: result.model,
        classified_at: Time.current,
        needs_review: result.needs_review?,
        review_state: nil
      )
      Applications::IngestEmail.call(email)
    end
  end
end
