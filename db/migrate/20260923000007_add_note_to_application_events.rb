class AddNoteToApplicationEvents < ActiveRecord::Migration[8.1]
  def change
    # For updates you add by hand (no email behind them), e.g. "rejected on a call".
    add_column :application_events, :note, :string
  end
end
