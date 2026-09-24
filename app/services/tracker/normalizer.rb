# Turns company names, roles and sender domains into stable grouping keys.
module Tracker
  module Normalizer
    COMPANY_SUFFIXES = %w[
      inc incorporated ltd limited pvt private llc llp plc corp corporation
      technologies technology solutions
    ].freeze

    # Second-level labels to skip when picking the company label out of a domain
    # (careers.acme.co.in -> "acme").
    GENERIC_LABELS = %w[com co org net ac gov edu in uk io ai us].freeze

    module_function

    # "Acme Technologies Pvt. Ltd." -> "acme"
    def company_key(name)
      words = strip_punctuation(name).split
      words.pop while words.size > 1 && COMPANY_SUFFIXES.include?(words.last)
      words.join(" ").presence
    end

    # "Software Engineer II (Backend) - R12345" -> "software engineer ii"
    def role_key(role)
      text = role.to_s.gsub(/\([^)]*\)|\[[^\]]*\]/, " ") # drop (Backend), [Remote]
      text = text.sub(/\s[-–|]\s*(req|job)?\s*#?\s*[a-z]*\d+\s*\z/i, " ") # trailing req IDs
      strip_punctuation(text).presence
    end

    # Company label from a sender domain, or nil when the domain can't identify the
    # employer (an ATS, job board or personal mail provider).
    def domain_company_key(domain)
      domain = domain.to_s.downcase.strip
      return if domain.empty? || ats_domain(domain) || personal_domain?(domain)

      labels = domain.split(".")
      labels.pop while labels.size > 1 && GENERIC_LABELS.include?(labels.last)
      labels.last
    end

    # The configured ATS domain that `domain` belongs to, if any.
    def ats_domain(domain)
      domain = domain.to_s.downcase
      Tracker.config[:ats_domains].find { |ats| domain == ats || domain.end_with?(".#{ats}") }
    end

    def personal_domain?(domain)
      Tracker.config[:personal_domains].include?(domain.to_s.downcase)
    end

    def strip_punctuation(text)
      text.to_s.downcase.gsub("&", " and ").gsub(/[^\p{Alnum}\s]/, " ").squish
    end
  end
end
