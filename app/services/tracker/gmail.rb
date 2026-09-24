# Gmail access: Auth (OAuth + token), Client (API calls), MessageParser.
module Tracker
  module Gmail
    # Google rejected our token (expired, revoked) or Gmail was never connected.
    class AuthExpired < StandardError; end
  end
end
