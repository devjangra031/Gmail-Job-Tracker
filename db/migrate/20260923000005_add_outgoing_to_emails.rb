class AddOutgoingToEmails < ActiveRecord::Migration[8.1]
  def change
    # True when the candidate sent the email (e.g. applying by mail with a CV).
    add_column :emails, :outgoing, :boolean, null: false, default: false
  end
end
