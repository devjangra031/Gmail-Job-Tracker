# A job application. Everything except company/role/source/notes is derived from
# its events by Applications::InferStatus — never edit derived_* by hand.
class Application < ApplicationRecord
  has_many :events, -> { order(:occurred_at, :id) },
           class_name: "ApplicationEvent", dependent: :destroy, inverse_of: :application
  has_many :emails, dependent: :nullify

  validates :company_name, :company_key, :source, presence: true
  validates :derived_status, inclusion: { in: Tracker::EVENT_KINDS }

  scope :terminal, -> { where(derived_status: Tracker::TERMINAL_KINDS) }
  scope :active, -> { where.not(derived_status: Tracker::TERMINAL_KINDS) }

  # Ghosted: not finished (no rejection/offer/withdrawal) and nothing heard for N
  # days, whether they never replied at all or went quiet after an interview.
  # Computed at query time, because "no activity in N days" changes as time passes.
  scope :ghosted, ->(days = Tracker.config[:ghost_after_days], now: Time.current) {
    active.where(last_activity_at: ...(now - days.days))
  }

  def terminal?
    Tracker::TERMINAL_KINDS.include?(derived_status)
  end

  def ghosted?(days = Tracker.config[:ghost_after_days], now: Time.current)
    !terminal? && last_activity_at.present? && last_activity_at < now - days.days
  end

  OUTCOMES = {
    "awaiting" => "Awaiting reply", "in_progress" => "In progress", "ghosted" => "Ghosted",
    "rejection" => "Rejected", "offer" => "Offer", "withdrawn" => "Withdrawn"
  }.freeze

  STAGE_LABELS = {
    "applied" => "Applied", "shortlisted" => "Shortlisted", "recruiter_outreach" => "Recruiter contact",
    "ai_screen" => "AI screen",
    "assessment" => "Assessment", "interview_scheduled" => "Interview scheduled",
    "interview_completed" => "Interviewed", "rejection" => "Rejected", "offer" => "Offer",
    "withdrawn" => "Withdrawn", "other" => "Other"
  }.freeze

  # The headline answer: did they reply, and how did it end? (keys of OUTCOMES)
  def outcome(now: Time.current)
    return derived_status if terminal?
    return "ghosted" if ghosted?(now: now)

    derived_status == "applied" ? "awaiting" : "in_progress"
  end

  def outcome_label(now: Time.current)
    OUTCOMES.fetch(outcome(now: now))
  end

  # Where it stands in detail, e.g. "Interview scheduled · round 2".
  def stage_label
    label = STAGE_LABELS.fetch(derived_status, derived_status.humanize)
    derived_round.positive? && !terminal? ? "#{label} · round #{derived_round}" : label
  end

  # The application's path as dated steps, e.g.
  #   Applied 11 Sep → R1 AI screening 13 Sep → R2 technical round 17 Sep → Rejected 20 Sep
  # One step per round (its first email; reminders and confirmations fold in, and
  # reschedules are counted), plus applied, recruiter contact and the outcome.
  Step = Data.define(:kind, :label, :at, :round, :reschedules, :scheduled_at, :completed, :note, :manual)

  def journey
    steps = []
    events.group_by { |event| event.round_number.to_i.positive? ? event.round_number : "#{event.kind}-#{event.id}" }
          .each_value do |group|
      first = group.first
      case first.kind
      when "applied"
        steps << Step.new(kind: "applied", label: "Applied", at: first.occurred_at, round: nil,
                          reschedules: 0, scheduled_at: nil, completed: false, note: first.note,
                          manual: first.manual?) unless steps.any? { |s| s.kind == "applied" }
      when "other"
        next
      else
        round = first.round_number.to_i.positive? ? first.round_number : nil
        label = group.filter_map(&:round_label).first || STAGE_LABELS.fetch(first.kind, first.kind.humanize)
        steps << Step.new(kind: first.kind, label: label, at: first.occurred_at, round: round,
                          reschedules: group.count(&:is_reschedule),
                          scheduled_at: group.select(&:scheduled_at).max_by(&:occurred_at)&.scheduled_at,
                          completed: group.any? { |e| e.kind == "interview_completed" },
                          note: group.filter_map(&:note).first, manual: group.all?(&:manual?))
      end
    end
    steps.sort_by(&:at)
  end

  def days_since_last_activity(now: Time.current)
    return unless last_activity_at
    ((now - last_activity_at) / 1.day).floor
  end

  # Events grouped under their round number (nil = not a round, e.g. rejection).
  def rounds
    events.group_by(&:round_number)
  end
end
