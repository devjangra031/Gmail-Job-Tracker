require "cgi"

module Tracker
  class Classifier
    module Cleaner
      # Soft hyphen, combining grapheme joiner (LinkedIn pads snippets with it),
      # zero-width spaces/joiners, word joiner, BOM.
      INVISIBLE = /[­͏​-‏⁠﻿]/
      URL = %r{<?(?:https?://|mailto:)[^\s>]+>?}

      module_function

      def text(value)
        CGI.unescapeHTML(value.to_s)
           .gsub(INVISIBLE, "")
           .gsub(URL, " ")
           .gsub(/[-_=]{5,}/, " | ")
           .squish
      end

      # LinkedIn's plain-text parts are often empty, but every tracking link names
      # the email type (…page:email_email_jobs_application_rejected_01;…), which is reliable.
      def linkedin_type(body)
        CGI.unescape(body.to_s)[/page:email_(?:email_)?([a-z_]+?)(?:_\d+)?;/, 1]
      rescue ArgumentError
        nil
      end
    end
  end
end
