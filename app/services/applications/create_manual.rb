# Adds an application with no email behind it (applied via a portal that sends
# no confirmation, a referral, etc.). Later emails from the same company/role
# will group into it automatically.
module Applications
  class CreateManual
    def self.call(company_name:, role: nil, source: nil, applied_on: nil, notes: nil)
      application = Application.new(
        company_name: company_name.to_s.strip,
        company_key: Tracker::Normalizer.company_key(company_name),
        role: role.to_s.strip.presence,
        role_key: Tracker::Normalizer.role_key(role),
        source: source.to_s.strip.presence || "manual",
        notes: notes.to_s.strip.presence,
        manual: true
      )
      applied_on = Date.iso8601(applied_on.to_s) rescue Date.current

      if application.company_key.nil?
        application.errors.add(:company_name, "can't be blank")
        return application
      end
      if applied_on > Date.current
        application.errors.add(:base, "Applied date can't be in the future")
        return application
      end

      ApplicationRecord.transaction do
        application.save!
        application.events.create!(kind: "applied", occurred_at: applied_on.in_time_zone.change(hour: 12))
        InferStatus.call(application)
      end
      IngestEmail.adopt_orphans
      application
    end
  end
end
