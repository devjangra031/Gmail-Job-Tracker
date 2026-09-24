require "rails_helper"

RSpec.describe Application do
  describe "#journey" do
    let(:sep) { ->(day) { Time.zone.parse("2026-09-#{day} 10:00") } }

    it "lays out applied → AI assessment → second round → rejection with their dates" do
      application, = ingest(
        create_email(category: "applied", thread_id: "a", sent_at: sep.(11)),
        create_email(category: "ai_screen", thread_id: "b", sent_at: sep.(13), round_label: "AI assessment"),
        create_email(category: "interview_scheduled", thread_id: "c", sent_at: sep.(17), round_hint: 2,
                     round_label: "Round 2", scheduled_at: sep.(19)),
        create_email(category: "interview_scheduled", thread_id: "c", sent_at: sep.(18), is_reschedule: true,
                     scheduled_at: sep.(19) + 1.day),
        create_email(category: "rejection", thread_id: "d", sent_at: sep.(20))
      )

      steps = application.journey.map { |s| [ s.label, s.round, s.at.day, s.reschedules ] }

      expect(steps).to eq([
        [ "Applied", nil, 11, 0 ],
        [ "AI assessment", 1, 13, 0 ],
        [ "Round 2", 2, 17, 1 ],   # the reschedule on the 18th folds into round 2
        [ "Rejected", nil, 20, 0 ]
      ])
    end

    it "folds reminders into their round and leaves out notifications like 'application viewed'" do
      application, = ingest(
        create_email(category: "applied", thread_id: "a", sent_at: sep.(1)),
        create_email(category: "other", thread_id: "v", sent_at: sep.(2)),
        create_email(category: "interview_scheduled", thread_id: "b", sent_at: sep.(3), round_hint: 1, scheduled_at: sep.(5)),
        create_email(category: "interview_scheduled", thread_id: "reminder", sent_at: sep.(4), scheduled_at: sep.(5)),
        create_email(category: "interview_completed", thread_id: "b", sent_at: sep.(6))
      )

      journey = application.journey

      expect(journey.map(&:kind)).to eq(%w[applied interview_scheduled])
      expect(journey.last).to have_attributes(completed: true, scheduled_at: sep.(5))
    end
  end

  describe "ghosting (no reply for ghost_after_days, whatever stage was reached)" do
    let(:now) { Time.current }

    def application_with(*emails)
      ingest(*emails).first
    end

    it "counts an application that never got a reply" do
      application = application_with(create_email(category: "applied", sent_at: now - 31.days))

      expect(application.ghosted?(now: now)).to be(true)
      expect(Application.ghosted(now: now)).to include(application)
    end

    it "counts an application that went quiet after an interview" do
      application = application_with(
        create_email(category: "applied", sent_at: now - 60.days),
        create_email(category: "interview_scheduled", sent_at: now - 40.days)
      )

      expect(application.ghosted?(now: now)).to be(true)
    end

    it "does not count one with a reply inside the window" do
      application = application_with(
        create_email(category: "applied", sent_at: now - 60.days),
        create_email(category: "interview_scheduled", sent_at: now - 10.days)
      )

      expect(application.ghosted?(now: now)).to be(false)
      expect(Application.ghosted(now: now)).not_to include(application)
    end

    it "is not rescued from ghosting by your own follow-up email" do
      application = application_with(
        create_email(category: "applied", sent_at: now - 40.days),
        create_email(category: "other", outgoing: true, subject: "Any update?", sent_at: now - 5.days)
      )

      expect(application.ghosted?(now: now)).to be(true)
      expect(application.last_activity_at).to be_within(1.second).of(now - 40.days)
    end

    it "still counts an application you sent by email yourself" do
      application = application_with(create_email(category: "applied", outgoing: true, sent_at: now - 3.days))

      expect(application.events.map(&:kind)).to eq([ "applied" ])
    end

    it "never counts a finished application (rejection, offer, withdrawn)" do
      application = application_with(
        create_email(category: "applied", sent_at: now - 90.days),
        create_email(category: "rejection", sent_at: now - 80.days)
      )

      expect(application.ghosted?(now: now)).to be(false)
    end
  end
end
