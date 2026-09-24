# Derives round numbers, reschedule flags and the application's status from its
# event timeline. Deterministic and idempotent: running it twice changes nothing.
#
# Rules (events walked oldest-first):
# - applied is round 0.
# - ai_screen / assessment / interview_scheduled start a new round when:
#     * they carry an explicit round_hint (round = max(hint, previous + 1), so our
#       numbering never goes backwards; the company's wording stays in round_label),
#     * or they're in a thread with no earlier round,
#     * or their thread's round is a different kind of stage.
#   Otherwise they stay in their thread's round (a reschedule, confirmation or
#   reminder); a reschedule updates that round's scheduled_at to the latest value.
# - From any thread, an event joins an existing round of the same kind when it
#   repeats that round's number ("L1" sent again) or its exact time slot (a
#   calendar reminder). A reschedule in a new thread joins the latest such round.
# - Joining a round with a different scheduled_at counts as a reschedule even if
#   the email doesn't say so (recruiters often just send a fresh invite).
# - interview_completed joins its thread's round, else the latest round.
# - rejection / offer / withdrawn are terminal and don't consume a round;
#   shortlisted, recruiter_outreach and other don't either.
# - derived_status: the latest terminal event if any, else the most advanced stage
#   (highest round, then stage rank). derived_round: highest round reached.
module Applications
  class InferStatus
    ROUND_STARTING_KINDS = %w[ai_screen assessment interview_scheduled].freeze
    INTERVIEW_KINDS = %w[interview_scheduled interview_completed].freeze

    STAGE_RANK = {
      "applied" => 0,
      "shortlisted" => 1,
      "recruiter_outreach" => 2,
      "ai_screen" => 3,
      "assessment" => 4,
      "interview_scheduled" => 5,
      "interview_completed" => 6
    }.freeze

    Input = Data.define(:kind, :occurred_at, :thread_id, :round_hint, :round_label,
                        :scheduled_at, :reschedule_flag) do
      def initialize(kind:, occurred_at:, thread_id: nil, round_hint: nil, round_label: nil,
                     scheduled_at: nil, reschedule_flag: false)
        super
      end
    end

    Assignment = Data.define(:round_number, :is_reschedule)
    Round = Struct.new(:number, :kind, :thread_id, :hint, :label, :scheduled_at, keyword_init: true)
    Result = Data.define(:assignments, :rounds, :status, :round, :first_applied_at, :last_activity_at)

    def self.call(application)
      new(application).call
    end

    # Pure core: takes Inputs, returns a Result whose assignments line up with inputs.
    def self.infer(inputs)
      Inference.new(inputs).run
    end

    def initialize(application)
      @application = application
    end

    def call
      events = @application.events.includes(:email).to_a
      result = self.class.infer(events.map { |event| input_for(event) })

      ApplicationRecord.transaction do
        events.zip(result.assignments).each do |event, assignment|
          event.round_number = assignment.round_number
          event.is_reschedule = assignment.is_reschedule
          event.save! if event.changed?
        end

        @application.update!(
          derived_status: result.status,
          derived_round: result.round,
          first_applied_at: result.first_applied_at,
          last_activity_at: result.last_activity_at
        )
      end

      result
    end

    private

    # The classifier's view lives on the email, so recomputing never feeds our own
    # output back in. Manual events carry their own flag.
    def input_for(event)
      email = event.email
      Input.new(
        kind: event.kind,
        occurred_at: event.occurred_at,
        thread_id: email&.thread_id,
        round_hint: email&.round_hint,
        round_label: event.round_label,
        scheduled_at: event.scheduled_at,
        reschedule_flag: email ? email.is_reschedule : event.is_reschedule
      )
    end

    class Inference
      def initialize(inputs)
        @inputs = inputs
        @rounds = []
        @thread_rounds = {}
        @current = 0
      end

      def run
        assignments = Array.new(@inputs.size)
        ordered = @inputs.each_with_index.sort_by { |input, index| [ input.occurred_at, index ] }

        ordered.each do |input, index|
          assignments[index] = assign(input)
        end

        Result.new(
          assignments: assignments,
          rounds: @rounds.map(&:dup),
          status: status(assignments),
          round: @rounds.map(&:number).max || 0,
          first_applied_at: first_applied_at,
          last_activity_at: @inputs.map(&:occurred_at).max
        )
      end

      private

      def assign(input)
        case input.kind
        when "applied"
          Assignment.new(round_number: 0, is_reschedule: false)
        when *ROUND_STARTING_KINDS
          if (round = existing_round_for(input))
            moved = input.scheduled_at && round.scheduled_at && input.scheduled_at != round.scheduled_at
            round.scheduled_at = input.scheduled_at if input.scheduled_at
            round.label ||= input.round_label
            Assignment.new(round_number: round.number, is_reschedule: input.reschedule_flag || moved.present?)
          else
            Assignment.new(round_number: start_round(input).number, is_reschedule: false)
          end
        when "interview_completed"
          round = (input.thread_id && @thread_rounds[input.thread_id]) || @rounds.last
          round ||= start_round(input)
          Assignment.new(round_number: round.number, is_reschedule: false)
        else
          Assignment.new(round_number: nil, is_reschedule: false)
        end
      end

      def existing_round_for(input)
        thread_round = input.thread_id && @thread_rounds[input.thread_id]

        if thread_round && same_stage?(thread_round.kind, input.kind) &&
           (input.round_hint.nil? || input.reschedule_flag || input.round_hint == thread_round.hint)
          return thread_round
        end

        candidates = @rounds.reverse.select { |round| same_stage?(round.kind, input.kind) }

        # The same numbered round announced again, e.g. a fresh "L1 interview" invite.
        if input.round_hint && (match = candidates.find { |round| round.hint == input.round_hint })
          return match
        end

        # The same time slot is the same interview, e.g. a calendar reminder.
        if input.scheduled_at && (match = candidates.find { |round| round.scheduled_at == input.scheduled_at })
          return match
        end

        # A reschedule sent in a new thread: join the latest matching round.
        candidates.first if input.reschedule_flag && input.round_hint.nil?
      end

      def start_round(input)
        number = [ input.round_hint.to_i, @current + 1 ].max
        @current = number
        round = Round.new(number: number, kind: input.kind, thread_id: input.thread_id,
                          hint: input.round_hint, label: input.round_label,
                          scheduled_at: input.scheduled_at)
        @rounds << round
        @thread_rounds[input.thread_id] = round if input.thread_id
        round
      end

      def same_stage?(a, b)
        a == b || (INTERVIEW_KINDS.include?(a) && INTERVIEW_KINDS.include?(b))
      end

      def status(assignments)
        terminal = @inputs.select { |i| Tracker::TERMINAL_KINDS.include?(i.kind) }
        return terminal.max_by(&:occurred_at).kind if terminal.any?

        staged = @inputs.zip(assignments).select { |input, _| STAGE_RANK.key?(input.kind) }
        return "applied" if staged.empty?

        input, _ = staged.max_by do |input, assignment|
          [ assignment.round_number.to_i, STAGE_RANK[input.kind], input.occurred_at ]
        end
        input.kind
      end

      def first_applied_at
        applied = @inputs.select { |i| i.kind == "applied" }
        (applied.presence || @inputs).map(&:occurred_at).min
      end
    end
  end
end
