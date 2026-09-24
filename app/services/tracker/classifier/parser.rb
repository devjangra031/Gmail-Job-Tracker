module Tracker
  class Classifier
    # Validates the model's JSON. Lenient about harmless formatting ("2" for 2,
    # "null" for null, code fences) and strict about meaning (unknown category,
    # confidence outside 0..1, unparseable dates).
    module Parser
      STRING_LIMITS = { company: 120, role: 160, round_label: 60, reason: 200 }.freeze

      module_function

      # Returns [attributes, nil] or [nil, "what was wrong"].
      def parse(text)
        data = JSON.parse(text.to_s.strip.sub(/\A```(?:json)?\s*/, "").sub(/\s*```\z/, ""))
        return [ nil, "not a JSON object" ] unless data.is_a?(Hash)

        category = data["category"].to_s.strip.downcase
        return [ nil, "unknown category #{data['category'].inspect}" ] unless Tracker::EMAIL_CATEGORIES.include?(category)

        confidence = number(data["confidence"])
        return [ nil, "confidence must be a number from 0 to 1" ] unless confidence&.between?(0, 1)

        round_hint = integer(data["round_hint"])
        return [ nil, "round_hint must be an integer or null" ] if round_hint == :invalid

        is_reschedule = boolean(data["is_reschedule"])
        return [ nil, "is_reschedule must be true or false" ] if is_reschedule.nil?

        scheduled_at = time(data["scheduled_at"])
        return [ nil, "scheduled_at must be ISO 8601 or null" ] if scheduled_at == :invalid

        attributes = STRING_LIMITS.to_h { |key, limit| [ key, string(data[key.to_s], limit) ] }
        [ attributes.merge(category:, confidence:, round_hint:, is_reschedule:, scheduled_at:), nil ]
      rescue JSON::ParserError
        [ nil, "not valid JSON" ]
      end

      def blank?(value)
        value.nil? || (value.is_a?(String) && (value.strip.empty? || value.strip.casecmp?("null")))
      end

      def string(value, limit)
        return if blank?(value)
        value.to_s.squish.truncate(limit)
      end

      def number(value)
        Float(value)
      rescue ArgumentError, TypeError
        nil
      end

      def integer(value)
        return if blank?(value)
        return value if value.is_a?(Integer)
        return value.to_i if value.is_a?(String) && value.strip.match?(/\A\d+\z/)
        return value.to_i if value.is_a?(Float) && value == value.floor

        :invalid
      end

      def boolean(value)
        return false if value.nil?
        return value if [ true, false ].include?(value)
        { "true" => true, "false" => false }[value.to_s.strip.downcase]
      end

      def time(value)
        return if blank?(value)

        text = value.to_s.strip
        begin
          Time.iso8601(text).in_time_zone
        rescue ArgumentError
          begin
            Time.zone.parse(text) || :invalid
          rescue ArgumentError
            :invalid
          end
        end
      end
    end
  end
end
