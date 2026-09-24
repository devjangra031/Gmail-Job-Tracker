# Entry point after an email is classified (or re-reviewed): regroup it and
# rebuild every application it touches.
module Applications
  class IngestEmail
    def self.call(email)
      previous = email.application
      current = AssignEmail.call(email)
      created = current&.previously_new_record?

      Rebuild.call(previous) if previous && previous != current && Application.exists?(previous.id)
      adopt_orphans if created
      Rebuild.call(current) if current && Application.exists?(current.id)
      current
    end

    # Emails that couldn't be placed earlier (an "other" such as "your application
    # was viewed", processed before the application existed) get another chance
    # whenever a new application appears. Mail arrives newest-first, so this matters.
    def self.adopt_orphans
      Email.eligible.where(application_id: nil).find_each do |orphan|
        adopted = AssignEmail.call(orphan)
        Rebuild.call(adopted) if adopted
      end
    end
  end
end
