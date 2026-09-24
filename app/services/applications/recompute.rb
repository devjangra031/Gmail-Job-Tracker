# Bulk rebuilds, used by the tracker:recompute and tracker:regroup rake tasks.
module Applications
  module Recompute
    module_function

    # Rebuild events + status for every application. IDs stay stable.
    def all
      Application.find_each { |application| Rebuild.call(application) }
    end

    # Throw away all email-derived grouping and regroup every email from scratch.
    # Use after changing normalization rules. Application IDs will change, but
    # updates you added by hand are carried over to the matching application.
    def regroup
      ApplicationRecord.transaction do
        carried = hand_added_updates_on_email_applications

        Email.update_all(application_id: nil)
        ApplicationEvent.where.not(email_id: nil).delete_all
        Application.where(manual: false).destroy_all

        Email.eligible.order(:sent_at, :id).each { |email| AssignEmail.call(email) }
        carried.each { |owner, attributes| home_for(owner).events.create!(attributes) }
        all
      end
    end

    EVENT_FIELDS = %w[kind occurred_at scheduled_at round_label note is_reschedule].freeze

    def hand_added_updates_on_email_applications
      ApplicationEvent.where(email_id: nil).includes(:application).select { |e| !e.application.manual? }.map do |event|
        owner = event.application.slice(:company_name, :company_key, :role, :role_key, :source)
        [ owner, event.attributes.slice(*EVENT_FIELDS) ]
      end
    end

    # Same company and role if it still exists, else same company, else a manual one.
    def home_for(owner)
      Application.find_by(company_key: owner["company_key"], role_key: owner["role_key"]) ||
        Application.where(company_key: owner["company_key"]).order(:id).first ||
        Application.create!(owner.merge("manual" => true))
    end
  end
end
