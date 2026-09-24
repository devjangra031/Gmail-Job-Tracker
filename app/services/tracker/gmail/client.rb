require "google/apis/gmail_v1"

# Thin wrapper over the Gmail API: search with pagination, fetch messages, a
# client-side rate limit (gmail_requests_per_second), and exponential backoff on
# 429 / 5xx / "rate limit" or "quota exceeded" 403s.
module Tracker
  module Gmail
    class Client
      class Unavailable < StandardError; end

      def initialize(service: nil, credentials: nil, max_retries: Tracker.config[:gmail_max_retries],
                     requests_per_second: Tracker.config[:gmail_requests_per_second],
                     sleeper: ->(seconds) { sleep(seconds) },
                     clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        @service = service || Google::Apis::GmailV1::GmailService.new.tap do |gmail|
          gmail.client_options.application_name = "job-tracker"
          gmail.authorization = credentials || Auth.credentials!
        end
        @max_retries = max_retries
        @min_interval = requests_per_second.to_f.positive? ? 1.0 / requests_per_second.to_f : 0
        @sleeper = sleeper
        @clock = clock
        @next_request_at = nil
      end

      # "<query> after:<epoch> before:<epoch>" covering whole local days, inclusive.
      def self.query_for(date_from:, date_to:, base: Tracker.config[:gmail_query])
        after = date_from.in_time_zone.beginning_of_day.to_i
        before = (date_to + 1).in_time_zone.beginning_of_day.to_i
        "#{base.squish} after:#{after} before:#{before}"
      end

      def message_ids(query)
        ids = []
        page_token = nil
        loop do
          page = with_retries do
            @service.list_user_messages("me", q: query, max_results: 500, page_token: page_token)
          end
          ids.concat(Array(page.messages).map(&:id))
          page_token = page.next_page_token
          break if page_token.blank?
        end
        ids
      end

      def message(id)
        with_retries { @service.get_user_message("me", id, format: "full") }
      end

      private

      # Spaces requests at least 1/requests_per_second apart, so a sync stays under
      # Gmail's per-minute quota instead of bursting into it and backing off.
      def throttle
        return if @min_interval.zero?

        now = @clock.call
        @sleeper.call(@next_request_at - now) if @next_request_at && @next_request_at > now
        @next_request_at = [ now, @next_request_at || now ].max + @min_interval
      end

      def with_retries
        attempt = 0
        begin
          throttle
          yield
        rescue Google::Apis::AuthorizationError, Signet::AuthorizationError => e
          raise AuthExpired, e.message
        rescue Google::Apis::RateLimitError, Google::Apis::ServerError, Google::Apis::TransmissionError,
               Google::Apis::ClientError => e
          raise if e.is_a?(Google::Apis::ClientError) && !rate_limited_403?(e)

          attempt += 1
          raise Unavailable, "Gmail kept failing after #{@max_retries} retries: #{e.message}" if attempt > @max_retries

          @sleeper.call([ 2**attempt, 60 ].min)
          retry
        end
      end

      # Gmail signals per-user limits as a 403: "rateLimitExceeded" / "userRateLimitExceeded",
      # or "Quota exceeded for quota metric 'Total Query Cost' ... per minute per user".
      def rate_limited_403?(error)
        error.status_code == 403 && error.message.to_s.match?(/rate ?limit|quota exceeded/i)
      end
    end
  end
end
