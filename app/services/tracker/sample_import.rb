# Upserts the emails that explore.rb dumped into sample_emails.json, and reads the
# optional answer key in db/seeds/sample_labels.yml. Both files are gitignored.
module Tracker
  module SampleImport
    PATH = Rails.root.join("sample_emails.json")
    LABELS_PATH = Rails.root.join("db/seeds/sample_labels.yml")

    module_function

    def available?
      PATH.exist?
    end

    # Creates or refreshes the raw fields; never touches classification.
    def import
      JSON.parse(PATH.read).map do |raw|
        email = Email.find_or_initialize_by(gmail_message_id: raw.fetch("id"))
        email.assign_attributes(
          thread_id: raw.fetch("thread_id"),
          sent_at: Time.zone.parse(raw.fetch("date")),
          from_address: raw["from"],
          from_domain: nil,
          subject: raw["subject"],
          body: raw["body"],
          raw_snippet: raw["snippet"],
          outgoing: outgoing?(raw["from"]),
          linkedin_type: Classifier::Cleaner.linkedin_type(raw["body"])
        )
        email.save!
        email
      end
    end

    def labels
      return {} unless LABELS_PATH.exist?

      YAML.safe_load_file(LABELS_PATH) || {}
    end

    # The sample has no Gmail labels, so recognise your own address from
    # MY_EMAIL_ADDRESSES in .env (comma-separated). Sync uses the SENT label instead.
    def outgoing?(from)
      mine = ENV.fetch("MY_EMAIL_ADDRESSES", "").split(",").map { |a| a.strip.downcase }.reject(&:empty?)
      address = (from.to_s[/<([^>]+)>/, 1] || from).to_s.strip.downcase
      mine.include?(address)
    end
  end
end
