class CreateApplicationEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :application_events do |t|
      t.references :application, null: false, foreign_key: true
      t.references :email, foreign_key: true
      t.string :kind, null: false
      t.integer :round_number
      t.string :round_label
      t.datetime :occurred_at, null: false
      t.datetime :scheduled_at
      t.boolean :is_reschedule, null: false, default: false

      t.timestamps
    end

    add_index :application_events, [ :application_id, :occurred_at ]
    add_index :application_events, :scheduled_at
  end
end
