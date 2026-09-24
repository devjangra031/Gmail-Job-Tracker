module Tracker
  class Classifier
    # What the model sees for one email, cleaned to spend tokens on words, not URLs.
    Input = Data.define(:from, :subject, :sent_at, :body, :snippet, :outgoing, :linkedin_type) do
      def initialize(linkedin_type: nil, **rest)
        super
      end

      def self.from_email(email)
        new(from: email.from_address, subject: email.subject, sent_at: email.sent_at,
            body: email.body, snippet: email.raw_snippet, outgoing: email.outgoing,
            linkedin_type: email.linkedin_type)
      end
    end
  end
end
