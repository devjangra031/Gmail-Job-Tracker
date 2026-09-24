# Filters and sorts stored applications for the list page. Works only on what's
# already in the database — it never fetches mail (that's the Sync page).
module Applications
  class Filter
    RANGES = { "7" => "Last 7 days", "30" => "Last 30 days", "60" => "Last 60 days",
               "90" => "Last 90 days", "custom" => "Custom…" }.freeze
    SORTS = {
      "company" => "applications.company_name", "role" => "applications.role",
      "source" => "applications.source", "status" => "applications.derived_status",
      "round" => "applications.derived_round", "applied" => "applications.first_applied_at",
      "activity" => "applications.last_activity_at",
      "idle" => "applications.last_activity_at" # most idle = oldest activity
    }.freeze

    attr_reader :q, :outcome, :source, :range, :from, :to, :sort, :dir

    def initialize(params = {}, now: Time.current)
      @q = params[:q].to_s.strip
      @outcome = params[:outcome].presence_in(Application::OUTCOMES.keys)
      @source = params[:source].presence
      @range = params[:range].presence_in(RANGES.keys)
      @from = parse_date(params[:from])
      @to = parse_date(params[:to])
      @sort = params[:sort].presence_in(SORTS.keys) || "activity"
      @dir = params[:dir] == "asc" ? "asc" : "desc"
      @now = now
    end

    def relation
      scope = Application.all
      scope = search(scope)
      scope = by_outcome(scope)
      scope = scope.where(source: source) if source
      scope = by_date(scope)
      scope.order(Arel.sql("#{SORTS.fetch(sort)} #{effective_dir} NULLS LAST"), id: :desc)
    end

    # Params for a column header link: same filters, toggled direction.
    def sort_params(column, current_params)
      next_dir = sort == column && dir == "desc" ? "asc" : "desc"
      current_params.merge(sort: column, dir: next_dir)
    end

    def active?
      q.present? || outcome || source || range
    end

    private

    # "Days idle" reads naturally as biggest first, i.e. oldest activity first.
    def effective_dir
      return (dir == "desc" ? "asc" : "desc") if sort == "idle"

      dir
    end

    def search(scope)
      return scope if q.empty?

      pattern = "%#{Application.sanitize_sql_like(q.downcase)}%"
      scope.where("LOWER(applications.company_name) LIKE :p OR LOWER(applications.role) LIKE :p", p: pattern)
    end

    def by_outcome(scope)
      cutoff = @now - Tracker.config[:ghost_after_days].days
      case outcome
      when nil then scope
      when "ghosted" then scope.merge(Application.ghosted(now: @now))
      when "awaiting" then scope.active.where(derived_status: "applied").where(last_activity_at: cutoff..)
      when "in_progress" then scope.active.where.not(derived_status: "applied").where(last_activity_at: cutoff..)
      else scope.where(derived_status: outcome)
      end
    end

    def by_date(scope)
      case range
      when nil then scope
      when "custom"
        scope = scope.where(first_applied_at: from.in_time_zone.beginning_of_day..) if from
        scope = scope.where(first_applied_at: ..to.in_time_zone.end_of_day) if to
        scope
      else
        scope.where(first_applied_at: (@now - range.to_i.days)..)
      end
    end

    def parse_date(value)
      Date.iso8601(value.to_s) if value.present?
    rescue Date::Error
      nil
    end
  end
end
