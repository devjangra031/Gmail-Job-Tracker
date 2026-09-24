class SyncRun < ApplicationRecord
  STATES = %w[running done failed].freeze
  PHASES = %w[fetching classifying].freeze

  validates :state, inclusion: { in: STATES }
  validates :phase, inclusion: { in: PHASES }
  validates :started_at, presence: true

  scope :recent, -> { order(started_at: :desc) }
  scope :running, -> { where(state: "running") }

  def running?
    state == "running"
  end

  # Percent of the current phase done (fetching new mail, then classifying).
  def progress
    return 100 unless running?

    if phase == "fetching"
      emails_new.zero? ? 0 : (emails_fetched * 100 / emails_new)
    else
      emails_to_classify.zero? ? 100 : (emails_classified * 100 / emails_to_classify)
    end
  end
end
