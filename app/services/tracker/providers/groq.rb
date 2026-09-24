# Everything Groq-specific lives here: endpoint, auth, request parameters,
# rate-limit handling and model listing. Never talks to api.openai.com.
module Tracker
  module Providers
    class Groq
      URI_BASE = "https://api.groq.com/openai/v1".freeze
      MODEL_GONE_CODES = %w[model_decommissioned model_not_found].freeze

      attr_reader :model

      def initialize(api_key: ENV["GROQ_API_KEY"], model: Tracker.config[:groq_model],
                     reasoning_effort: Tracker.config[:groq_reasoning_effort],
                     max_retries: Tracker.config[:groq_max_retries],
                     max_wait: Tracker.config[:groq_max_wait_seconds],
                     sleeper: ->(seconds) { sleep(seconds) })
        raise StopRun, "GROQ_API_KEY is not set. Add it to .env and restart." if api_key.blank?

        @client = OpenAI::Client.new(access_token: api_key, uri_base: URI_BASE,
                                     request_timeout: 60, log_errors: false)
        @model = model
        @reasoning_effort = reasoning_effort
        @max_retries = max_retries
        @max_wait = max_wait
        @sleeper = sleeper
      end

      def complete(system:, messages:)
        parameters = {
          model: @model,
          temperature: 0,
          response_format: { type: "json_object" },
          messages: [ { role: "system", content: system }, *messages ]
        }
        parameters[:reasoning_effort] = @reasoning_effort if @reasoning_effort.present?

        response = with_retries { @client.chat(parameters: parameters) }
        Completion.new(text: response.dig("choices", 0, "message", "content").to_s,
                       tokens: response.dig("usage", "total_tokens"))
      end

      def models
        with_retries { @client.models.list }.fetch("data", []).map { |model| model["id"] }.sort
      end

      private

      def with_retries
        attempt = 0
        begin
          yield
        rescue Faraday::TooManyRequestsError => e
          attempt += 1
          wait = retry_after(e)
          message = error_message(e)
          if daily_limit?(message) || (wait && wait > @max_wait)
            raise RateLimited, "Groq rate limit reached, stopping for now: #{message}"
          end
          raise RateLimited, "Groq still rate-limiting after #{@max_retries} retries: #{message}" if attempt > @max_retries

          @sleeper.call(wait || backoff(attempt))
          retry
        rescue Faraday::ServerError, Faraday::ConnectionFailed => e
          attempt += 1
          raise RequestFailed, "Groq unavailable after #{@max_retries} retries (#{e.class.name.demodulize})" if attempt > @max_retries

          @sleeper.call(backoff(attempt))
          retry
        rescue Faraday::UnauthorizedError, Faraday::ForbiddenError
          raise StopRun, "Groq rejected the API key. Check GROQ_API_KEY in .env."
        rescue Faraday::ClientError => e
          code = error_code(e)
          raise InvalidOutput, error_message(e) if code == "json_validate_failed"
          if MODEL_GONE_CODES.include?(code)
            raise StopRun, "Groq model #{@model} is unavailable (#{code}). Run `bin/rails tracker:models` " \
                           "and update groq_model in config/tracker.yml."
          end
          raise RequestFailed, "Groq request failed: #{error_message(e)}"
        end
      end

      def backoff(attempt)
        [ 2**attempt, 60 ].min
      end

      def retry_after(error)
        # Faraday's header hash is case-insensitive only through #[] (not #dig).
        headers = error.response&.[](:headers) || {}
        value = headers["retry-after"] || headers["Retry-After"]
        Float(value) if value.present?
      rescue ArgumentError
        nil
      end

      # Groq reports daily quotas as "tokens per day (TPD)" / "requests per day (RPD)".
      def daily_limit?(message)
        message.match?(/per day|\b(TPD|RPD)\b/i)
      end

      def error_payload(error)
        body = error.response&.dig(:body)
        body = JSON.parse(body) if body.is_a?(String)
        body.is_a?(Hash) ? body.fetch("error", {}) : {}
      rescue JSON::ParserError
        {}
      end

      def error_message(error)
        error_payload(error)["message"].presence || "HTTP #{error.response&.dig(:status)}"
      end

      def error_code(error)
        error_payload(error)["code"]
      end
    end
  end
end
