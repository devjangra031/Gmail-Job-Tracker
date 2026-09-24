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

ActiveRecord::Schema[8.1].define(version: 2026_09_23_000001) do
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
end
