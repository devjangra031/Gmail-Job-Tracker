# Finds (or creates) the application an email belongs to and attaches it.
#
# 1. Same Gmail thread as an already-assigned email -> that application, always.
# 2. company_key + role_key match. If the email has a role, an application for the
#    same company with no role yet adopts it. If the email has no role, it joins the
#    company's most recently active application.
# 3. Otherwise a new application — except for "other", which only ever attaches.
#
# Emails that aren't eligible (job alerts, discarded, unconfirmed low confidence)
# are detached and never create anything. Returns the application or nil.
module Applications
  class AssignEmail
    NON_CREATING_KINDS = %w[other].freeze

    def self.call(email)
      new(email).call
    end

    def initialize(email)
      @email = email
    end

    def call
      unless @email.eligible?
        @email.update!(application: nil) if @email.application_id
        return
      end

      application = by_thread || by_company || create_application
      @email.update!(application: application) if application && @email.application_id != application.id
      application
    end

    private

    def by_thread
      Application.joins(:emails)
                 .where(emails: { thread_id: @email.thread_id })
                 .where.not(emails: { id: @email.id })
                 .first
    end

    def by_company
      return unless company_key

      scope = Application.where(company_key: company_key).order(last_activity_at: :desc, id: :desc)
      return scope.first unless role_key

      match = scope.find_by(role_key: role_key) || scope.find_by(role_key: nil)
      match&.update!(role: @email.extracted_role, role_key: role_key) if match && match.role_key.nil?
      match
    end

    def create_application
      return if company_key.nil? || NON_CREATING_KINDS.include?(@email.category)

      Application.create!(
        company_name: @email.extracted_company.presence&.strip || company_key.titleize,
        company_key: company_key,
        role: @email.extracted_role.presence&.strip,
        role_key: role_key,
        source: Tracker::Normalizer.ats_domain(@email.from_domain) || "direct",
        first_applied_at: @email.sent_at,
        last_activity_at: @email.sent_at
      )
    end

    def company_key
      return @company_key if defined?(@company_key)

      @company_key = Tracker::Normalizer.company_key(@email.extracted_company) ||
                     Tracker::Normalizer.domain_company_key(@email.from_domain)
    end

    def role_key
      return @role_key if defined?(@role_key)

      @role_key = Tracker::Normalizer.role_key(@email.extracted_role)
    end
  end
end
