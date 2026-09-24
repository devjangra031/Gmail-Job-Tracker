# LLM providers. A provider only turns (system, user) prompts into text and maps
# its own failures onto these errors, so swapping Groq for another OpenAI-style
# API means writing one class like Providers::Groq.
module Tracker
  module Providers
    class Error < StandardError; end

    # The whole run must stop (daily limit, bad key, retired model). Everything
    # classified so far is kept; the next run resumes with what's left.
    class StopRun < Error; end
    class RateLimited < StopRun; end

    # This one request failed after retries; the email stays unclassified.
    class RequestFailed < Error; end

    # The provider rejected or garbled the model's JSON output.
    class InvalidOutput < Error; end

    Completion = Data.define(:text, :tokens)

    def self.default
      Groq.new
    end
  end
end
