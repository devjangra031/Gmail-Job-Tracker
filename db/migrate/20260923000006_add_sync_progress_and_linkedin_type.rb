class AddSyncProgressAndLinkedinType < ActiveRecord::Migration[8.1]
  def change
    # LinkedIn's email type (from tracking links), captured before URLs are
    # stripped from the stored body. See Tracker::Classifier::Cleaner.
    add_column :emails, :linkedin_type, :string

    add_column :sync_runs, :phase, :string, null: false, default: "fetching" # fetching / classifying
    add_column :sync_runs, :emails_new, :integer, null: false, default: 0
    add_column :sync_runs, :emails_fetched, :integer, null: false, default: 0
    add_column :sync_runs, :emails_to_classify, :integer, null: false, default: 0
  end
end
