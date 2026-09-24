# Dashboard numbers, computed in Ruby over applications and their events
# (SQLite has no Groupdate support, and the data set is small).
#
# Definitions:
# - response: any event from the company after applying — AI screen, assessment,
#   recruiter contact, interview, rejection or offer. ("Application viewed" and
#   other notifications are not responses.)
# - funnel: applied -> screened (any response other than an outright rejection) ->
#   interviewed -> offer, by the furthest stage each application ever reached.
# - ghosted: not finished and no activity for ghost_after_days (see Application).
module Tracker
  class Analytics
    RESPONSE_KINDS = %w[shortlisted ai_screen assessment recruiter_outreach interview_scheduled
                        interview_completed rejection offer].freeze
    SCREEN_KINDS = %w[shortlisted ai_screen assessment recruiter_outreach].freeze
    INTERVIEW_KINDS = %w[interview_scheduled interview_completed].freeze
    STAGES = %w[applied screened interviewed offer].freeze

    attr_reader :applications, :now

    def initialize(applications = Application.all, now: Time.current)
      @applications = applications.includes(:events).to_a
      @now = now
    end

    def stats
      {
        total: applications.size,
        awaiting: applications.count { |a| a.outcome(now: now) == "awaiting" },
        in_progress: applications.count { |a| a.outcome(now: now) == "in_progress" },
        rejected: applications.count { |a| a.derived_status == "rejection" },
        offers: applications.count { |a| a.derived_status == "offer" },
        ghosted: applications.count { |a| a.ghosted?(now: now) }
      }
    end

    def funnel
      reached = STAGES.to_h { |stage| [ stage, applications.count { |a| STAGES.index(furthest_stage(a)) >= STAGES.index(stage) } ] }
      STAGES.each_with_index.map do |stage, index|
        count = reached[stage]
        previous = index.zero? ? nil : reached[STAGES[index - 1]]
        {
          stage: stage, count: count,
          percent_of_total: percent(count, applications.size),
          drop_off: previous ? percent(previous - count, previous) : nil
        }
      end
    end

    def rates
      total = applications.size
      {
        response: percent(applications.count { |a| first_response_at(a) }, total),
        rejection: percent(applications.count { |a| a.derived_status == "rejection" }, total),
        ghost: percent(stats[:ghosted], total)
      }
    end

    def timings
      to_response = applications.filter_map { |a| days_between(a.first_applied_at, first_response_at(a)) }
      to_rejection = applications.filter_map do |a|
        rejection = a.events.select { |e| e.kind == "rejection" }.map(&:occurred_at).min
        days_between(a.first_applied_at, rejection)
      end
      {
        median_first_response: percentile(to_response, 50),
        p90_first_response: percentile(to_response, 90),
        median_rejection: percentile(to_rejection, 50),
        responses_measured: to_response.size
      }
    end

    # { applications: {Date => n}, rejections: {Date => n} } per week or month,
    # with empty buckets filled in so charts don't skip gaps.
    def over_time(period)
      applied = applications.filter_map(&:first_applied_at)
      rejected = applications.flat_map { |a| a.events.select { |e| e.kind == "rejection" }.map(&:occurred_at) }
      buckets = bucket_range(applied + rejected, period)
      {
        applications: count_by(applied, buckets, period),
        rejections: count_by(rejected, buckets, period)
      }
    end

    def per_company
      applications.group_by(&:company_key).map do |_key, apps|
        {
          company: apps.first.company_name,
          apps: apps.sort_by { |a| a.first_applied_at || a.created_at },
          applications: apps.size,
          furthest_stage: apps.map { |a| furthest_stage(a) }.max_by { |stage| STAGES.index(stage) },
          outcome: apps.map { |a| a.outcome_label(now: now) }.tally.map { |label, n| n > 1 ? "#{n}× #{label}" : label }.join(", "),
          last_activity_at: apps.filter_map(&:last_activity_at).max
        }
      end.sort_by { |row| [ -row[:applications], -row[:last_activity_at].to_i ] }
    end

    def per_source
      applications.group_by(&:source).map do |source, apps|
        responded = apps.count { |a| first_response_at(a) }
        { source: source, applications: apps.size, responded: responded,
          response_rate: percent(responded, apps.size) }
      end.sort_by { |row| -row[:applications] }
    end

    # Active applications whose current interview/screen time is still ahead.
    def pipeline
      applications.reject(&:terminal?).filter_map do |application|
        upcoming = application.events.group_by(&:round_number).filter_map do |round, events|
          next unless round.to_i.positive?

          latest = events.select(&:scheduled_at).max_by(&:occurred_at)
          { round: round, label: events.filter_map(&:round_label).first, scheduled_at: latest.scheduled_at } if latest
        end.select { |r| r[:scheduled_at] >= now }.min_by { |r| r[:scheduled_at] }
        upcoming&.merge(application: application)
      end.sort_by { |row| row[:scheduled_at] }
    end

    def furthest_stage(application)
      kinds = application.events.map(&:kind)
      return "offer" if kinds.include?("offer")
      return "interviewed" if kinds.intersect?(INTERVIEW_KINDS)
      return "screened" if kinds.intersect?(SCREEN_KINDS)

      "applied"
    end

    def first_response_at(application)
      application.events.select { |e| RESPONSE_KINDS.include?(e.kind) }.map(&:occurred_at).min
    end

    private

    def percent(part, whole)
      whole.to_i.zero? ? 0 : (part * 100.0 / whole).round(1)
    end

    def days_between(from, to)
      return unless from && to && to >= from

      ((to - from) / 1.day).round(1)
    end

    def percentile(values, pct)
      return if values.empty?

      sorted = values.sort
      rank = (pct / 100.0) * (sorted.size - 1)
      lower = sorted[rank.floor]
      upper = sorted[rank.ceil]
      (lower + (upper - lower) * (rank - rank.floor)).round(1)
    end

    def bucket_start(time, period)
      date = time.in_time_zone.to_date
      period == :month ? date.beginning_of_month : date.beginning_of_week
    end

    def bucket_range(times, period)
      return [] if times.empty?

      first = bucket_start(times.min, period)
      last = bucket_start([ times.max, now ].max, period)
      step = period == :month ? 1.month : 1.week
      buckets = []
      cursor = first
      while cursor <= last
        buckets << cursor
        cursor += step
      end
      buckets
    end

    def count_by(times, buckets, period)
      counts = times.map { |t| bucket_start(t, period) }.tally
      buckets.to_h { |bucket| [ bucket, counts.fetch(bucket, 0) ] }
    end
  end
end
