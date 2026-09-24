# Rebuilds one application's email-backed events from its eligible emails, then
# re-runs InferStatus. Manual events (no email) are kept. A non-manual application
# left with no events is destroyed.
module Applications
  class Rebuild
    def self.call(application)
      new(application).call
    end

    def initialize(application)
      @application = application
    end

    def call
      ApplicationRecord.transaction do
        @application.events.where.not(email_id: nil).delete_all

        @application.emails.eligible.order(:sent_at, :id).select(&:company_event?).each do |email|
          @application.events.create!(
            email: email,
            kind: email.category,
            occurred_at: email.sent_at,
            round_label: email.round_label,
            scheduled_at: email.scheduled_at
          )
        end

        @application.events.reset
        if @application.events.empty? && !@application.manual?
          @application.emails.update_all(application_id: nil)
          @application.destroy!
        else
          InferStatus.call(@application)
        end
      end
      @application unless @application.destroyed?
    end
  end
end
