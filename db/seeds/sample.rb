# Loads your real sample_emails.json (from explore.rb). Emails the LLM hasn't
# classified yet get the hand labels from db/seeds/sample_labels.yml, if present;
# LLM results from `bin/rails tracker:classify_sample` are never overwritten.

unless Tracker::SampleImport.available?
  puts "No sample_emails.json (run `ruby explore.rb` to create it); skipping real sample."
  return
end

labels = Tracker::SampleImport.labels
labelled = 0

Tracker::SampleImport.import.sort_by(&:sent_at).each do |email|
  label = labels[email.gmail_message_id]
  next unless label && email.classifier_model.in?([ nil, "manual" ])

  email.update!(
    category: label["category"],
    extracted_company: label["company"],
    extracted_role: label["role"],
    round_label: label["round_label"],
    round_hint: label["round_hint"],
    is_reschedule: label["is_reschedule"] || false,
    scheduled_at: label["scheduled_at"],
    confidence: 1.0,
    classifier_reason: "hand label",
    classifier_model: "manual",
    classified_at: Time.current,
    needs_review: false
  )
  Applications::IngestEmail.call(email)
  labelled += 1
end

puts "Real sample loaded (#{labelled} hand-labelled)."
