# Seeds are additive and idempotent: records are upserted by gmail_message_id, so
# running `bin/rails db:seed` never touches mail synced from Gmail.
#
# Made-up demo data (fictional companies) is opt-in, so a reset never mixes it into
# your real data:  DEMO=1 bin/rails db:seed   ·   remove it: bin/rails tracker:remove_demo_data
#
#   db/seeds/synthetic.rb  made-up applications covering every inference case (DEMO=1 only)
#   db/seeds/sample.rb     your real sample_emails.json (+ hand labels), if present

load Rails.root.join("db/seeds/synthetic.rb") if ENV["DEMO"].present?
load Rails.root.join("db/seeds/sample.rb")

puts "Applications: #{Application.count}  Emails: #{Email.count}  " \
     "Unassigned: #{Email.where(application_id: nil).count}  Review queue: #{Email.review_queue.count}"
