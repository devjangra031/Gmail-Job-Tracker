require "rails_helper"

RSpec.describe Applications::InferStatus do
  let(:t0) { Time.zone.parse("2026-06-01 09:00") }

  def input(kind, day, thread: nil, hint: nil, label: nil, scheduled: nil, reschedule: false)
    described_class::Input.new(
      kind: kind, occurred_at: t0 + day.days, thread_id: thread, round_hint: hint,
      round_label: label, scheduled_at: scheduled, reschedule_flag: reschedule
    )
  end

  def rounds_of(result)
    result.assignments.map(&:round_number)
  end

  describe ".infer (pure rules)" do
    it "puts applied at round 0 with status applied" do
      result = described_class.infer([ input("applied", 0, thread: "a") ])

      expect(rounds_of(result)).to eq([ 0 ])
      expect(result).to have_attributes(status: "applied", round: 0, first_applied_at: t0, last_activity_at: t0)
    end

    it "keeps a reschedule in the same thread in the same round and updates scheduled_at" do
      first = t0 + 5.days
      moved = t0 + 7.days
      result = described_class.infer([
        input("applied", 0, thread: "a"),
        input("interview_scheduled", 2, thread: "b", scheduled: first),
        input("interview_scheduled", 3, thread: "b", scheduled: moved, reschedule: true)
      ])

      expect(rounds_of(result)).to eq([ 0, 1, 1 ])
      expect(result.assignments.map(&:is_reschedule)).to eq([ false, false, true ])
      expect(result.rounds.map(&:scheduled_at)).to eq([ moved ])
      expect(result).to have_attributes(status: "interview_scheduled", round: 1)
    end

    it "keeps a same-thread confirmation without a hint in the same round, not flagged as reschedule" do
      result = described_class.infer([
        input("interview_scheduled", 1, thread: "b"),
        input("interview_scheduled", 2, thread: "b")
      ])

      expect(rounds_of(result)).to eq([ 1, 1 ])
      expect(result.assignments.map(&:is_reschedule)).to eq([ false, false ])
    end

    it "uses an explicit round 2 hint even when no round 1 was seen" do
      result = described_class.infer([
        input("applied", 0, thread: "a"),
        input("interview_scheduled", 4, thread: "c", hint: 2, label: "Round 2")
      ])

      expect(rounds_of(result)).to eq([ 0, 2 ])
      expect(result.round).to eq(2)
    end

    it "starts a new round for an explicit hint inside the same thread" do
      result = described_class.infer([
        input("interview_scheduled", 1, thread: "b", hint: 1),
        input("interview_completed", 3, thread: "b"),
        input("interview_scheduled", 5, thread: "b", hint: 2)
      ])

      expect(rounds_of(result)).to eq([ 1, 1, 2 ])
    end

    it "never lets a company's own 'round 1' move our numbering backwards" do
      result = described_class.infer([
        input("ai_screen", 1, thread: "b"),
        input("interview_scheduled", 4, thread: "c", hint: 1, label: "Round 1")
      ])

      expect(rounds_of(result)).to eq([ 1, 2 ])
      expect(result.rounds.last.label).to eq("Round 1")
    end

    it "gives an AI screen and two human rounds their own round numbers" do
      result = described_class.infer([
        input("applied", 0, thread: "a"),
        input("ai_screen", 1, thread: "b", label: "AI screening"),
        input("interview_scheduled", 5, thread: "c", label: "technical round"),
        input("interview_completed", 7, thread: "c"),
        input("interview_scheduled", 10, thread: "d", label: "final")
      ])

      expect(rounds_of(result)).to eq([ 0, 1, 2, 2, 3 ])
      expect(result).to have_attributes(status: "interview_scheduled", round: 3)
      expect(result.rounds.map(&:label)).to eq([ "AI screening", "technical round", "final" ])
    end

    it "gives an assessment its own round even in the AI screen's thread" do
      result = described_class.infer([
        input("ai_screen", 1, thread: "b"),
        input("assessment", 2, thread: "b")
      ])

      expect(rounds_of(result)).to eq([ 1, 2 ])
      expect(result.status).to eq("assessment")
    end

    it "makes rejection after round 2 terminal without consuming a round" do
      result = described_class.infer([
        input("applied", 0, thread: "a"),
        input("interview_scheduled", 3, thread: "b"),
        input("interview_scheduled", 8, thread: "c"),
        input("rejection", 12, thread: "c")
      ])

      expect(rounds_of(result)).to eq([ 0, 1, 2, nil ])
      expect(result).to have_attributes(status: "rejection", round: 2)
    end

    it "uses the latest terminal event when there are several" do
      result = described_class.infer([
        input("offer", 10, thread: "a"),
        input("withdrawn", 12, thread: "a")
      ])

      expect(result.status).to eq("withdrawn")
    end

    it "attaches interview_completed in a new thread to the latest round" do
      result = described_class.infer([
        input("interview_scheduled", 1, thread: "b"),
        input("interview_completed", 3, thread: "z")
      ])

      expect(rounds_of(result)).to eq([ 1, 1 ])
      expect(result.status).to eq("interview_completed")
    end

    it "attaches a reschedule sent in a new thread to the latest matching round" do
      result = described_class.infer([
        input("interview_scheduled", 1, thread: "b"),
        input("interview_scheduled", 2, thread: "z", reschedule: true)
      ])

      expect(rounds_of(result)).to eq([ 1, 1 ])
      expect(result.assignments.last.is_reschedule).to be(true)
    end

    it "treats a re-sent 'L1' invite in a new thread, plus calendar reminders, as one rescheduled round" do
      monday = t0 + 1.day + 22.hours
      tuesday = t0 + 2.days + 22.hours
      result = described_class.infer([
        input("interview_scheduled", 0, thread: "invite-1", hint: 1, scheduled: monday),
        input("interview_scheduled", 0.5, thread: "calendar-1", hint: 1, scheduled: monday),
        input("interview_scheduled", 1, thread: "invite-2", hint: 1, scheduled: tuesday),
        input("interview_scheduled", 1.5, thread: "calendar-2", scheduled: tuesday)
      ])

      expect(rounds_of(result)).to eq([ 1, 1, 1, 1 ])
      expect(result.assignments.map(&:is_reschedule)).to eq([ false, false, true, false ])
      expect(result.rounds.map(&:scheduled_at)).to eq([ tuesday ])
    end

    it "still starts a new round for an unnumbered interview in a new thread at a new time" do
      result = described_class.infer([
        input("interview_scheduled", 1, thread: "b", scheduled: t0 + 3.days),
        input("interview_scheduled", 5, thread: "c", scheduled: t0 + 8.days)
      ])

      expect(rounds_of(result)).to eq([ 1, 2 ])
    end

    it "treats shortlisted as progress past applied, without a round" do
      result = described_class.infer([
        input("applied", 0, thread: "a"),
        input("shortlisted", 3, thread: "b")
      ])

      expect(rounds_of(result)).to eq([ 0, nil ])
      expect(result).to have_attributes(status: "shortlisted", round: 0)
    end

    it "does not give recruiter_outreach or other a round" do
      result = described_class.infer([
        input("recruiter_outreach", 0, thread: "a"),
        input("other", 1, thread: "a")
      ])

      expect(rounds_of(result)).to eq([ nil, nil ])
      expect(result).to have_attributes(status: "recruiter_outreach", round: 0, first_applied_at: t0)
    end

    it "prefers a later round over a higher stage rank in an earlier round" do
      result = described_class.infer([
        input("interview_completed", 1, thread: "b"),
        input("assessment", 4, thread: "c")
      ])

      expect(result.status).to eq("assessment")
    end

    it "orders by occurred_at regardless of input order" do
      result = described_class.infer([
        input("interview_scheduled", 5, thread: "c"),
        input("ai_screen", 1, thread: "b")
      ])

      expect(rounds_of(result)).to eq([ 2, 1 ])
    end
  end

  describe ".call (end to end from emails)" do
    it "persists the reschedule-in-same-thread case" do
      application, = ingest(
        create_email(category: "applied", thread_id: "t1", sent_at: t0),
        create_email(category: "interview_scheduled", thread_id: "t2", sent_at: t0 + 2.days,
                     scheduled_at: t0 + 5.days),
        create_email(category: "interview_scheduled", thread_id: "t2", sent_at: t0 + 3.days,
                     scheduled_at: t0 + 6.days, is_reschedule: true)
      )

      expect(application.events.map { |e| [ e.kind, e.round_number, e.is_reschedule ] }).to eq([
        [ "applied", 0, false ],
        [ "interview_scheduled", 1, false ],
        [ "interview_scheduled", 1, true ]
      ])
      expect(application).to have_attributes(derived_status: "interview_scheduled", derived_round: 1)
    end

    it "persists AI screen then two human rounds then rejection" do
      application, = ingest(
        create_email(category: "applied", thread_id: "t1", sent_at: t0),
        create_email(category: "ai_screen", thread_id: "t2", sent_at: t0 + 1.day),
        create_email(category: "interview_scheduled", thread_id: "t3", sent_at: t0 + 5.days, round_hint: 1),
        create_email(category: "interview_scheduled", thread_id: "t4", sent_at: t0 + 9.days, round_hint: 2),
        create_email(category: "rejection", thread_id: "t4", sent_at: t0 + 14.days)
      )

      expect(application.events.map(&:round_number)).to eq([ 0, 1, 2, 3, nil ])
      expect(application).to have_attributes(derived_status: "rejection", derived_round: 3,
                                             first_applied_at: t0, last_activity_at: t0 + 14.days)
    end

    it "is idempotent" do
      application, = ingest(
        create_email(category: "applied", sent_at: t0),
        create_email(category: "interview_scheduled", sent_at: t0 + 2.days)
      )

      expect { described_class.call(application) }.not_to(change { application.reload.updated_at })
      expect { described_class.call(application) }.not_to(change { application.events.map(&:updated_at) })
    end
  end
end
