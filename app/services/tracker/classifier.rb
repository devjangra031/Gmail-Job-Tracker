# Classifies one email: builds the prompt, asks the provider, validates the JSON.
# Invalid output is retried once with the problem spelled out; a second failure
# returns an invalid Result, which lands the email in the review queue.
module Tracker
  class Classifier
    Result = Data.define(:category, :company, :role, :round_label, :round_hint, :is_reschedule,
                         :scheduled_at, :confidence, :reason, :model, :tokens, :valid) do
      def needs_review?(threshold = Tracker.config[:review_threshold])
        !valid || confidence.to_f < threshold
      end
    end

    def initialize(provider: Providers.default)
      @provider = provider
    end

    def model
      @provider.model
    end

    def classify(input)
      messages = [ { role: "user", content: Prompt.user_message(input) } ]
      tokens = 0
      problem = nil

      2.times do
        text = nil
        begin
          completion = @provider.complete(system: Prompt.system, messages: messages)
          tokens += completion.tokens.to_i
          text = completion.text
          attributes, problem = Parser.parse(text)
          return Result.new(**attributes, model: model, tokens: tokens, valid: true) if attributes
        rescue Providers::InvalidOutput => e
          problem = e.message
        end

        messages += [ { role: "assistant", content: text.truncate(2000) } ] if text.present?
        messages += [ { role: "user", content: "That reply was invalid (#{problem}). " \
                                               "Reply again with only the JSON object described above." } ]
      end

      Result.new(category: nil, company: nil, role: nil, round_label: nil, round_hint: nil,
                 is_reschedule: false, scheduled_at: nil, confidence: 0, model: model, tokens: tokens,
                 reason: "Invalid classifier output twice: #{problem}".truncate(200), valid: false)
    end
  end
end
