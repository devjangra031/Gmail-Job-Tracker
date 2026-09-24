class CreateApplications < ActiveRecord::Migration[8.1]
  def change
    create_table :applications do |t|
      t.string :company_name, null: false
      t.string :company_key, null: false
      t.string :role
      t.string :role_key
      t.string :source, null: false
      t.datetime :first_applied_at
      t.datetime :last_activity_at
      t.string :derived_status, null: false, default: "applied"
      t.integer :derived_round, null: false, default: 0
      t.boolean :manual, null: false, default: false
      t.text :notes

      t.timestamps
    end

    add_index :applications, [ :company_key, :role_key ]
    add_index :applications, :derived_status
    add_index :applications, :source
    add_index :applications, :last_activity_at
  end
end
