# Console table of sample classifications, scored against the hand-labelled
# answer key when one exists.
module Tracker
  class SampleReport
    def initialize(emails, labels)
      @emails = emails.select(&:classified_at).reject { |e| e.classifier_model == "manual" }
      @labels = labels
    end

    def print(out = $stdout)
      return out.puts("Nothing classified by the LLM yet.") if @emails.empty?

      out.puts format("%-3s %-44s %-20s %-22s %-24s %-4s %-5s %s",
                      "#", "subject", "category", "company", "role", "rnd", "conf", "check")
      @emails.each_with_index do |email, index|
        out.puts format("%-3d %-44s %-20s %-22s %-24s %-4s %-5s %s",
                        index + 1, email.subject.to_s.truncate(44), email.category || "INVALID",
                        email.extracted_company.to_s.truncate(22), email.extracted_role.to_s.truncate(24),
                        email.round_hint, email.confidence&.round(2), check(email))
      end

      scored = @emails.select { |email| @labels.key?(email.gmail_message_id) }
      return if scored.empty?

      category_ok = scored.count { |email| category_ok?(email) }
      company_ok = scored.count { |email| company_ok?(email) }
      out.puts "\nAgainst the answer key (#{scored.size} emails): category #{category_ok}/#{scored.size}, " \
               "company #{company_ok}/#{scored.size}, sent to review #{scored.count(&:needs_review)}"

      scored.reject { |email| category_ok?(email) && company_ok?(email) }.each do |email|
        label = @labels[email.gmail_message_id]
        out.puts "  - #{email.subject.to_s.truncate(70)}\n" \
                 "      expected #{label['category']} / #{label['company'].inspect}, " \
                 "got #{email.category.inspect} / #{email.extracted_company.inspect} (#{email.classifier_reason})"
      end
    end

    private

    def check(email)
      marks = []
      marks << "REVIEW" if email.needs_review
      if @labels.key?(email.gmail_message_id)
        marks << (category_ok?(email) && company_ok?(email) ? "ok" : "MISMATCH")
      end
      marks.join(" ")
    end

    def category_ok?(email)
      @labels.dig(email.gmail_message_id, "category") == email.category
    end

    def company_ok?(email)
      expected = @labels.dig(email.gmail_message_id, "company")
      Normalizer.company_key(expected) == Normalizer.company_key(email.extracted_company)
    end
  end
end
