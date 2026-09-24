class ApplicationEvent < ApplicationRecord
  belongs_to :application, inverse_of: :events
  belongs_to :email, optional: true

  validates :kind, inclusion: { in: Tracker::EVENT_KINDS }
  validates :occurred_at, presence: true

  def terminal?
    Tracker::TERMINAL_KINDS.include?(kind)
  end

  def manual?
    email_id.nil?
  end
end
