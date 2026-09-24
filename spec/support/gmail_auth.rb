# Specs must never read the real credentials.json / token.yaml in the project
# folder; pretend Gmail is connected unless a spec says otherwise.
RSpec.configure do |config|
  config.before do
    allow(Tracker::Gmail::Auth).to receive(:status).and_return(:connected)
  end
end
