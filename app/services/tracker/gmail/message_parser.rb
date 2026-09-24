# Turns a Gmail API message into Email attributes. Prefers the text/plain part,
# unless it's a stub like "Please Enable HTML", in which case the HTML is
# converted to text. URLs are dropped (after reading LinkedIn's email type from
# them) and the result is capped at Email::BODY_LIMIT characters.
module Tracker
  module Gmail
    module MessageParser
      STUB_TEXT = /enable html|html (version|email)|view (this|it) in (your|a) browser/i
      STUB_LENGTH = 40
      BLOCK_TAGS = %w[br p div tr li h1 h2 h3 h4 h5 h6 table section].freeze

      module_function

      def call(message)
        headers = (message.payload&.headers || []).to_h { |h| [ h.name.downcase, h.value.to_s ] }
        plain = parts(message.payload, "text/plain").map { |part| decode(part) }.join("\n")
        html = parts(message.payload, "text/html").map { |part| decode(part) }.join("\n")

        {
          gmail_message_id: message.id,
          thread_id: message.thread_id,
          sent_at: Time.zone.at(message.internal_date.to_i / 1000),
          from_address: headers["from"],
          subject: headers["subject"],
          body: body_text(plain, html),
          raw_snippet: CGI.unescapeHTML(message.snippet.to_s),
          outgoing: Array(message.label_ids).include?("SENT"),
          linkedin_type: Classifier::Cleaner.linkedin_type("#{plain}\n#{html}")
        }
      end

      def body_text(plain, html)
        text = stub?(plain) && html.present? ? html_to_text(html) : plain
        text = html_to_text(html) if text.blank? && html.present?
        clean(text).truncate(Email::BODY_LIMIT, omission: "")
      end

      def stub?(plain)
        stripped = plain.to_s.strip
        stripped.length < STUB_LENGTH || (stripped.length < 200 && stripped.match?(STUB_TEXT))
      end

      def html_to_text(html)
        doc = Nokogiri::HTML(html)
        doc.css("script, style, head, title").remove
        doc.css(BLOCK_TAGS.join(", ")).each { |node| node.add_next_sibling(Nokogiri::XML::Text.new("\n", doc)) }
        doc.text
      end

      # Keeps line breaks (for reading in the UI); drops URLs and invisible padding.
      def clean(text)
        text.to_s
            .gsub(Classifier::Cleaner::INVISIBLE, "")
            .gsub(Classifier::Cleaner::URL, "")
            .gsub(/\r\n?/, "\n")
            .gsub(/[ \t ]+/, " ")
            .gsub(/ *\n */, "\n")
            .gsub(/\n{3,}/, "\n\n")
            .strip
      end

      # All non-attachment parts of a MIME type, depth first.
      def parts(part, mime_type, found = [])
        return found if part.nil?

        found << part if part.mime_type == mime_type && part.filename.blank? && part.body&.data.present?
        Array(part.parts).each { |child| parts(child, mime_type, found) }
        found
      end

      # The API client has already base64url-decoded body.data into bytes.
      def decode(part)
        content_type = part.headers&.find { |h| h.name.casecmp?("Content-Type") }&.value.to_s
        charset = content_type[/charset="?([^";\s]+)/i, 1] || "UTF-8"
        text = part.body.data.dup
        begin
          text.force_encoding(charset)
        rescue ArgumentError
          text.force_encoding("UTF-8")
        end
        text.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
      end
    end
  end
end
