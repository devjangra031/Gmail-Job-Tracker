class CreateSyncRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :sync_runs do |t|
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.string :state, null: false, default: "running"
      t.integer :emails_found, null: false, default: 0
      t.integer :emails_classified, null: false, default: 0
      t.integer :errors_count, null: false, default: 0
      t.text :last_error
      t.date :date_from
      t.date :date_to

      t.timestamps
    end

    add_index :sync_runs, :state
  end
end
