namespace :tracker do
  desc "Rebuild every application's events and status from its emails (IDs stay stable)"
  task recompute: :environment do
    Applications::Recompute.all
    puts "Recomputed #{Application.count} applications."
  end

  desc "Regroup all emails into applications from scratch (after changing normalization)"
  task regroup: :environment do
    Applications::Recompute.regroup
    puts "Regrouped into #{Application.count} applications."
  end

  desc "Remove the made-up demo data (seed-* emails and the Harborview manual app); real mail is untouched"
  task remove_demo_data: :environment do
    # Read-only check: Tracker::Sync.running? would "reap" the server's live sync,
    # because this separate process can't see the server's thread.
    abort "A sync is running; wait for it to finish first." if SyncRun.running.exists?

    demo_emails = Email.where("gmail_message_id LIKE ?", "seed-%")
    touched = Application.where(id: demo_emails.select(:application_id)).to_a
    demo_manual = Application.where(manual: true, company_key: "harborview", notes: "Applied through a referral.")

    ApplicationRecord.transaction do
      ApplicationEvent.where(email_id: demo_emails.select(:id)).delete_all
      removed_emails = demo_emails.delete_all
      removed_manual = demo_manual.destroy_all.size
      # Applications left with no emails are demo-only; any that also hold real mail are rebuilt.
      touched.each { |application| Applications::Rebuild.call(application.reload) }
      puts "Removed #{removed_emails} demo emails and #{removed_manual} demo manual application(s). " \
           "#{Application.count} applications remain."
    end
  end

  desc "Re-apply the free local rules (suggestion filter, LinkedIn/Cutshort rules) to already-classified mail. No Groq calls"
  task reapply_rules: :environment do
    changed = 0
    # Only mail nobody has reviewed by hand; a human decision always wins.
    Email.classified.where(review_state: nil).find_each do |email|
      result = Tracker::ClassifyEmails.local_result(email)
      next unless result
      next if result.category == email.category && result.company == email.extracted_company &&
              result.role == email.extracted_role

      puts "  #{email.subject.to_s.truncate(70)}: #{email.category.inspect} -> #{result.category}" \
           "#{" (#{result.company})" if result.company}"
      Tracker::ClassifyEmails.apply(email, result)
      changed += 1
    end
    puts "Updated #{changed} email(s)."
  end

  desc "List the model IDs Groq currently serves"
  task models: :environment do
    provider = Tracker::Providers::Groq.new
    configured = Tracker.config[:groq_model]
    ids = provider.models
    ids.each { |id| puts(id == configured ? "#{id}   <- configured" : id) }
    puts "\nConfigured model #{configured} is NOT available; update groq_model in config/tracker.yml." unless ids.include?(configured)
  rescue Tracker::Providers::Error => e
    abort e.message
  end

  desc "Classify sample_emails.json with Groq and report accuracy. LIMIT=n, FORCE=1 to redo"
  task classify_sample: :environment do
    abort "sample_emails.json not found. Run `ruby explore.rb` first." unless Tracker::SampleImport.available?

    emails = Tracker::SampleImport.import
    pending = ENV["FORCE"] ? emails : emails.reject { |e| e.classified_at && e.classifier_model != "manual" }
    pending = pending.first(Integer(ENV["LIMIT"])) if ENV["LIMIT"]

    begin
      classifier = Tracker::Classifier.new
    rescue Tracker::Providers::Error => e
      abort e.message
    end

    puts "Classifying #{pending.size} of #{emails.size} sample emails with #{classifier.model} " \
         "(#{Tracker.config[:groq_delay_seconds]}s apart)..."
    summary = Tracker::ClassifyEmails.call(pending, classifier: classifier,
                                           on_progress: ->(**) { print "." })
    puts

    Tracker::SampleReport.new(emails.map(&:reload), Tracker::SampleImport.labels).print

    puts "\nClassified #{summary.classified}, errors #{summary.errors}, tokens #{summary.tokens}" \
         "#{" (~#{summary.tokens / summary.classified}/email)" if summary.classified.positive?}."
    puts "Last error: #{summary.last_error}" if summary.last_error && !summary.stopped
    if summary.stopped
      puts "STOPPED: #{summary.last_error}"
      puts "Everything classified so far is saved; run the task again later to resume."
    end
  end
end
