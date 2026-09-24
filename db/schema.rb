# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_23_000002) do
  create_table "applications", force: :cascade do |t|
    t.string "company_key", null: false
    t.string "company_name", null: false
    t.datetime "created_at", null: false
    t.integer "derived_round", default: 0, null: false
    t.string "derived_status", default: "applied", null: false
    t.datetime "first_applied_at"
    t.datetime "last_activity_at"
    t.boolean "manual", default: false, null: false
    t.text "notes"
    t.string "role"
    t.string "role_key"
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.index ["company_key", "role_key"], name: "index_applications_on_company_key_and_role_key"
    t.index ["derived_status"], name: "index_applications_on_derived_status"
    t.index ["last_activity_at"], name: "index_applications_on_last_activity_at"
    t.index ["source"], name: "index_applications_on_source"
  end

  create_table "emails", force: :cascade do |t|
    t.integer "application_id"
    t.text "body"
    t.string "category"
    t.datetime "classified_at"
    t.string "classifier_model"
    t.string "classifier_reason"
    t.decimal "confidence", precision: 4, scale: 3
    t.datetime "created_at", null: false
    t.string "extracted_company"
    t.string "extracted_role"
    t.string "from_address"
    t.string "from_domain"
    t.string "gmail_message_id", null: false
    t.boolean "is_reschedule", default: false, null: false
    t.boolean "needs_review", default: false, null: false
    t.text "raw_snippet"
    t.string "review_state"
    t.integer "round_hint"
    t.string "round_label"
    t.datetime "scheduled_at"
    t.datetime "sent_at", null: false
    t.string "subject"
    t.string "thread_id", null: false
    t.datetime "updated_at", null: false
    t.index ["application_id"], name: "index_emails_on_application_id"
    t.index ["classified_at"], name: "index_emails_on_classified_at"
    t.index ["gmail_message_id"], name: "index_emails_on_gmail_message_id", unique: true
    t.index ["needs_review"], name: "index_emails_on_needs_review"
    t.index ["sent_at"], name: "index_emails_on_sent_at"
    t.index ["thread_id"], name: "index_emails_on_thread_id"
  end

  add_foreign_key "emails", "applications"
end
