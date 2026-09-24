# Shared vocabulary and settings for the job tracker.
module Tracker
  # shortlisted: the company picked your application for the next step (Cutshort,
  # Naukri, Instahyre…) — a real reply, but not yet a round of its own.
  EVENT_KINDS = %w[
    applied shortlisted ai_screen assessment recruiter_outreach interview_scheduled
    interview_completed rejection offer withdrawn other
  ].freeze

  # The classifier may also return "job_alert"; those emails never become events.
  EMAIL_CATEGORIES = (EVENT_KINDS + %w[job_alert]).freeze

  TERMINAL_KINDS = %w[rejection offer withdrawn].freeze

  def self.config
    Rails.configuration.x.tracker
  end
end
