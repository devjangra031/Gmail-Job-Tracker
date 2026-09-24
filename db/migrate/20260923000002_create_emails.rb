class CreateEmails < ActiveRecord::Migration[8.1]
  def change
    create_table :emails do |t|
      t.string :gmail_message_id, null: false
      t.string :thread_id, null: false
      t.datetime :sent_at, null: false
      t.string :from_address
      t.string :from_domain
      t.string :subject
      t.text :body
      t.text :raw_snippet

      # Classifier output. Stored so inference can be recomputed without re-calling the LLM.
      t.string :category
      t.string :extracted_company
      t.string :extracted_role
      t.string :round_label
      t.integer :round_hint
      t.boolean :is_reschedule, null: false, default: false
      t.datetime :scheduled_at
      t.decimal :confidence, precision: 4, scale: 3
      t.string :classifier_reason
      t.string :classifier_model
      t.datetime :classified_at

      t.boolean :needs_review, null: false, default: false
      t.string :review_state # nil (not reviewed), "confirmed", "discarded"

      t.references :application, foreign_key: true

      t.timestamps
    end

    add_index :emails, :gmail_message_id, unique: true
    add_index :emails, :thread_id
    add_index :emails, :sent_at
    add_index :emails, :needs_review
    add_index :emails, :classified_at
  end
end
