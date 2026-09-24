# Tiny record builders; no factory library needed at this size.
module Builders
  def build_email(**attrs)
    @email_seq = (@email_seq || 0) + 1
    Email.new({
      gmail_message_id: "msg-#{@email_seq}-#{SecureRandom.hex(4)}",
      thread_id: "thread-#{@email_seq}",
      sent_at: Time.zone.parse("2026-06-01 10:00") + @email_seq.minutes,
      from_address: "Acme Recruiting <no-reply@acme.com>",
      subject: "Your application",
      category: "applied",
      extracted_company: "Acme",
      confidence: 0.95,
      classified_at: Time.current
    }.merge(attrs))
  end

  def create_email(**attrs)
    build_email(**attrs).tap(&:save!)
  end

  # Creates and ingests emails in order; returns the (reloaded) applications touched.
  def ingest(*emails)
    emails.each { |email| Applications::IngestEmail.call(email) }
    emails.filter_map { |email| email.reload.application }.uniq.each(&:reload)
  end
end

RSpec.configure { |config| config.include Builders }
