# One sync: fetch NEW mail for a date range from Gmail, then classify every
# unclassified email (including leftovers from an earlier run that stopped),
# broadcasting progress over Turbo Streams. Always resumable: fetched emails are
# saved before classification, and each classification is saved as it finishes.
module Tracker
  class Sync
    class AlreadyRunning < StandardError; end

    STREAM = "sync_runs".freeze
    BROADCAST_INTERVAL = 0.5 # seconds

    def self.start(date_from:, date_to:, async: true)
      TRACKER_SYNC_LOCK.synchronize do
        reap_stale!
        raise AlreadyRunning, "A sync is already running." if SyncRun.running.exists?

        run = SyncRun.create!(started_at: Time.current, date_from: date_from, date_to: date_to)
        if async
          TRACKER_SYNC_THREAD.set(Thread.new { Rails.application.executor.wrap { new(run).call } })
        else
          new(run).call
        end
        run
      end
    end

    def self.running?
      reap_stale!
      SyncRun.running.exists?
    end

    # A "running" row with no live thread means the server stopped mid-sync.
    def self.reap_stale!
      return if TRACKER_SYNC_THREAD.get&.alive?

      SyncRun.running.find_each do |run|
        run.update!(state: "failed", finished_at: Time.current,
                    last_error: "Interrupted (the server stopped during the sync). Sync again to resume.")
      end
    end

    def initialize(run, gmail: nil, classifier: nil, sleeper: ->(seconds) { sleep(seconds) })
      @run = run
      @gmail = gmail
      @classifier = classifier
      @sleeper = sleeper
    end

    def call
      fetch
      classify
    rescue Gmail::AuthExpired
      if Gmail::Auth.status == :connected
        # We had a token and Google rejected it: remember, so the UI offers Reconnect.
        Gmail::Auth.mark_expired!
        fail!("Gmail access has expired. Click “Reconnect Gmail”, then sync again.")
      else
        fail!("Gmail isn't connected. Click “Reconnect Gmail”, then sync again.")
      end
    rescue Gmail::Client::Unavailable, Providers::Error => e
      fail!(e.message)
    rescue StandardError => e
      Rails.logger.error("[sync] #{e.class}: #{e.message}\n#{e.backtrace&.first(10)&.join("\n")}")
      fail!("Unexpected error (#{e.class}): #{e.message}")
    end

    private

    def fetch
      gmail = @gmail || Gmail::Client.new
      ids = gmail.message_ids(Gmail::Client.query_for(date_from: @run.date_from, date_to: @run.date_to))
      known = Email.where(gmail_message_id: ids).pluck(:gmail_message_id).to_set
      new_ids = ids.reject { |id| known.include?(id) }
      @run.update!(emails_found: ids.size, emails_new: new_ids.size)
      broadcast(force: true)

      new_ids.each do |id|
        begin
          Email.create!(Gmail::MessageParser.call(gmail.message(id)))
        rescue Gmail::AuthExpired, Gmail::Client::Unavailable
          raise
        rescue ActiveRecord::RecordNotUnique
          # Already stored (e.g. a concurrent import); nothing to do.
        rescue StandardError => e
          @run.errors_count += 1
          @run.last_error = "Could not read message #{id}: #{e.message}"
        end
        @run.emails_fetched += 1
        @run.save!
        broadcast
      end
    end

    def classify
      pending = Email.unclassified.to_a
      @run.update!(phase: "classifying", emails_to_classify: pending.size)
      broadcast(force: true)

      fetch_errors = @run.errors_count
      summary = ClassifyEmails.call(
        pending,
        classifier: @classifier || Classifier.new,
        sleeper: @sleeper,
        on_progress: lambda do |classified:, errors:, **|
          @run.update!(emails_classified: classified, errors_count: fetch_errors + errors)
          broadcast
        end
      )

      if summary.stopped
        fail!("#{summary.last_error} Everything classified so far is saved; sync again later to finish the rest.")
      else
        @run.update!(state: "done", finished_at: Time.current, emails_classified: summary.classified,
                     errors_count: fetch_errors + summary.errors,
                     last_error: summary.last_error || @run.last_error)
        broadcast(force: true)
      end
    end

    def fail!(message)
      @run.update!(state: "failed", finished_at: Time.current, last_error: message)
      broadcast(force: true)
    end

    def broadcast(force: false)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return if !force && @last_broadcast && now - @last_broadcast < BROADCAST_INTERVAL

      @last_broadcast = now
      Turbo::StreamsChannel.broadcast_replace_to(STREAM, target: "sync_status", partial: "syncs/status",
                                                         locals: { run: @run })
    rescue StandardError => e
      Rails.logger.warn("[sync] broadcast failed: #{e.message}") # progress display must never break a sync
    end
  end
end
