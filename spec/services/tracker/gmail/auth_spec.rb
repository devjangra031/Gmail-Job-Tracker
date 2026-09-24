require "rails_helper"

RSpec.describe Tracker::Gmail::Auth do
  let(:dir) { Pathname(Dir.mktmpdir) }
  let(:client_file) { dir.join("credentials.json") }
  let(:token_file) { dir.join("token.yaml") }
  let(:flag_file) { dir.join("gmail_reauth_needed") }

  before do
    allow(described_class).to receive(:status).and_call_original # undo the suite-wide stub
    allow(described_class).to receive_messages(credentials_path: client_file, token_path: token_file,
                                               expired_flag_path: flag_file)
    client_file.write({ web: { client_id: "cid.apps.googleusercontent.com", client_secret: "shh" } }.to_json)
  end

  after { FileUtils.rm_rf(dir) }

  def store_token(**overrides)
    token = { client_id: "cid.apps.googleusercontent.com", access_token: "a", refresh_token: "r",
              scope: [ described_class::SCOPE ], expiration_time_millis: 0 }.merge(overrides)
    Google::Auth::Stores::FileTokenStore.new(file: token_file.to_s).store(described_class::USER_ID, token.to_json)
  end

  it "is connected with a stored read-only token, without spawning gcloud" do
    store_token
    expect(IO).not_to receive(:popen)

    expect(described_class.status).to eq(:connected)
  end

  it "is disconnected without a token, or with a token for another client or scope" do
    expect(described_class.status).to eq(:disconnected)

    store_token(client_id: "someone-else")
    expect(described_class.status).to eq(:disconnected)

    store_token(scope: [ "https://www.googleapis.com/auth/gmail.modify" ])
    expect(described_class.status).to eq(:disconnected)
  end

  it "reports expired once Google has rejected the token, until reconnected" do
    store_token
    described_class.mark_expired!

    expect(described_class.status).to eq(:expired)
  end

  it "reports a missing credentials.json" do
    client_file.delete

    expect(described_class.status).to eq(:no_client_file)
  end
end
