require "googleauth"
require "googleauth/stores/file_token_store"
require "socket"

# Read-only Gmail OAuth using a loopback redirect: a one-shot local listener on
# gmail_redirect_port receives Google's redirect, stores the token in token.yaml
# and sends the browser back to the app. (Same redirect URI as explore.rb, so
# nothing new needs registering in Google Cloud Console.)
module Tracker
  module Gmail
    module Auth
      SCOPE = "https://www.googleapis.com/auth/gmail.readonly".freeze
      USER_ID = "default".freeze
      LISTEN_TIMEOUT = 5.minutes

      module_function

      def credentials_path = Rails.root.join("credentials.json")
      def token_path = Rails.root.join("token.yaml")
      # Written when Google rejects the refresh token (≈7 days in Testing mode).
      def expired_flag_path = Rails.root.join("tmp/gmail_reauth_needed")

      def redirect_uri
        "http://localhost:#{Tracker.config[:gmail_redirect_port]}/"
      end

      # :no_client_file, :disconnected, :expired or :connected. Reads token.yaml only:
      # no network, and no credentials object (building one makes googleauth spawn
      # `gcloud` to look up a project id, which is slow on every page load).
      def status
        return :no_client_file unless credentials_path.exist?
        return :expired if expired_flag_path.exist?
        return :disconnected unless stored_token_usable?

        :connected
      rescue StandardError
        :disconnected
      end

      def stored_token_usable?
        return false unless token_path.exist?

        stored = Google::Auth::Stores::FileTokenStore.new(file: token_path.to_s).load(USER_ID)
        return false if stored.blank?

        token = JSON.parse(stored)
        client_id = Google::Auth::ClientId.from_file(credentials_path.to_s).id
        token["refresh_token"].present? && Array(token["scope"]).include?(SCOPE) &&
          token.fetch("client_id", client_id) == client_id
      end

      def credentials!
        raise AuthExpired, "Gmail is not connected." unless status == :connected

        authorizer.get_credentials(USER_ID)
      end

      def mark_expired!
        FileUtils.touch(expired_flag_path)
      end

      # Starts the one-shot listener and returns Google's consent URL.
      def start_reconnect!(return_to:)
        state = SecureRandom.hex(16)
        server = TCPServer.new("127.0.0.1", Tracker.config[:gmail_redirect_port])
        Thread.new { listen(server, state, return_to) }
        authorizer.get_authorization_url(base_url: redirect_uri, state: state)
      rescue Errno::EADDRINUSE
        raise AuthExpired, "Port #{Tracker.config[:gmail_redirect_port]} is busy. An earlier “Reconnect Gmail” may " \
                           "still be waiting (finish it in the Google tab, or wait up to 5 minutes), " \
                           "or explore.rb is running."
      end

      def authorizer
        client_id = Google::Auth::ClientId.from_file(credentials_path.to_s)
        store = Google::Auth::Stores::FileTokenStore.new(file: token_path.to_s)
        Google::Auth::UserAuthorizer.new(client_id, SCOPE, store, redirect_uri)
      end

      def listen(server, state, return_to)
        deadline = Time.now + LISTEN_TIMEOUT
        loop do
          break if Time.now > deadline
          next unless IO.select([ server ], nil, nil, 1)

          client = server.accept
          params = read_params(client)
          if params["code"].nil? && params["error"].nil?
            respond(client, 404, "Not found") # e.g. /favicon.ico
            next
          end

          if params["state"] == state && params["code"]
            begin
              authorizer.get_and_store_credentials_from_code(user_id: USER_ID, code: params["code"],
                                                             base_url: redirect_uri)
              FileUtils.rm_f(expired_flag_path)
              redirect(client, return_to)
            rescue StandardError => e
              respond(client, 500, "Could not complete Gmail authorization (#{e.class.name.demodulize}). " \
                                   "Close this tab and try again.")
            end
          else
            respond(client, 400, "Gmail authorization failed (#{params['error'] || 'state mismatch'}). " \
                                 "Close this tab and try again.")
          end
          break
        end
      rescue StandardError => e
        Rails.logger.error("[gmail auth] #{e.class}: #{e.message}")
      ensure
        server.close
      end

      def read_params(client)
        request_line = client.gets.to_s
        while (line = client.gets) && line != "\r\n"; end
        URI.decode_www_form(URI(request_line.split(" ")[1].to_s).query.to_s).to_h
      rescue URI::InvalidURIError
        {}
      end

      def redirect(client, location)
        client.print "HTTP/1.1 302 Found\r\nLocation: #{location}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
      ensure
        client.close
      end

      def respond(client, status, body)
        client.print "HTTP/1.1 #{status} X\r\nContent-Type: text/plain; charset=utf-8\r\n" \
                     "Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
      ensure
        client.close
      end
    end
  end
end
