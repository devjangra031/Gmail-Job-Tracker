# "Reconnect Gmail": starts the loopback listener and sends the browser to Google.
class GmailConnectionsController < ApplicationController
  def create
    url = Tracker::Gmail::Auth.start_reconnect!(return_to: sync_url)
    redirect_to url, allow_other_host: true
  rescue Tracker::Gmail::AuthExpired => e
    redirect_to sync_path, alert: e.message
  end
end
