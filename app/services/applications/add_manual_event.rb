# Records something that happened outside email (a rejection on a call, an
# interview arranged on WhatsApp, an offer in person) on an existing application.
# Manual events survive recompute and regroup, and feed InferStatus like any other.
module Applications
  class AddManualEvent
    KINDS = (Tracker::EVENT_KINDS - %w[other]).freeze

    def self.call(application, kind:, occurred_on:, note: nil, round_label: nil, scheduled_at: nil)
      event = application.events.build(kind: kind.to_s, note: note.to_s.strip.presence&.truncate(200),
                                       round_label: round_label.to_s.strip.presence&.truncate(60))
      date = parse_date(occurred_on)

      event.errors.add(:kind, "must be picked") unless KINDS.include?(event.kind)
      event.errors.add(:base, "Pick the date it happened") unless date
      event.errors.add(:base, "The date can't be in the future") if date && date > Date.current
      return event if event.errors.any?

      event.occurred_at = date.in_time_zone.change(hour: 12)
      event.scheduled_at = Time.zone.parse(scheduled_at.to_s) if scheduled_at.present?

      ApplicationRecord.transaction do
        event.save!
        InferStatus.call(application)
      end
      event
    end

    def self.parse_date(value)
      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end
  end
end
