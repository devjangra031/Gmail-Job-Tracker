# Fetches NEW mail from Gmail for a date range (unlike the list filters, which
# only filter what's already stored).
class SyncsController < ApplicationController
  def show
    Tracker::Sync.reap_stale!
    @run = SyncRun.recent.first
    @runs = SyncRun.recent.limit(10)
    @gmail_status = Tracker::Gmail::Auth.status
  end

  def create
    date_from = Date.iso8601(params[:date_from].to_s)
    date_to = Date.iso8601(params[:date_to].to_s)
    if date_from > date_to
      return redirect_to(sync_path, alert: "The start date must be on or before the end date.")
    end

    Tracker::Sync.start(date_from: date_from, date_to: date_to)
    redirect_to sync_path
  rescue Date::Error
    redirect_to sync_path, alert: "Pick both dates."
  rescue Tracker::Sync::AlreadyRunning => e
    redirect_to sync_path, alert: e.message
  end
end
