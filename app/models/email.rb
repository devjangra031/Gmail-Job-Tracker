# An email is an immutable event record plus the classifier's reading of it.
# Applications and their events are rebuilt from these.
class Email < ApplicationRecord
  REVIEW_STATES = %w[confirmed discarded].freeze
  BODY_LIMIT = 1500

  belongs_to :application, optional: true
  has_many :events, class_name: "ApplicationEvent", dependent: :nullify

  validates :gmail_message_id, presence: true, uniqueness: true
  validates :thread_id, :sent_at, presence: true
  validates :category, inclusion: { in: Tracker::EMAIL_CATEGORIES }, allow_nil: true
  validates :review_state, inclusion: { in: REVIEW_STATES }, allow_nil: true

  before_validation :derive_from_domain
  before_validation { self.body = body.to_s.truncate(BODY_LIMIT, omission: "") if body }

  scope :classified, -> { where.not(classified_at: nil) }
  scope :unclassified, -> { where(classified_at: nil) }
  scope :review_queue, -> { where(needs_review: true, review_state: nil) }

  # Emails that count: classified as a real event kind, not discarded, and either
  # confident or confirmed by a human in the review queue.
  scope :eligible, -> {
    where(category: Tracker::EVENT_KINDS)
      .where(review_state: [ nil, "confirmed" ])
      .where("emails.needs_review = ? OR emails.review_state = ?", false, "confirmed")
  }

  # Mail you sent only counts when it's you applying or withdrawing. A follow-up
  # like "any update?" is not activity from the company, so it must not reset the
  # ghosting clock or count as a reply.
  def company_event?
    !outgoing || %w[applied withdrawn].include?(category)
  end

  def eligible?
    Tracker::EVENT_KINDS.include?(category) &&
      review_state != "discarded" &&
      (!needs_review || review_state == "confirmed")
  end

  private

  def derive_from_domain
    return if from_address.blank? || from_domain.present?

    address = from_address[/<([^>]+)>/, 1] || from_address
    self.from_domain = address.split("@").last.to_s.strip.downcase.presence
  end
end
