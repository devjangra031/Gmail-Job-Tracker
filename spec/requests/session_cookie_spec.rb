require "rails_helper"

# Regression: with json 3.x, ActiveSupport crashed decoding the session cookie,
# so the first page worked and every page after it returned 500. Browsers always
# send the cookie back; single-request specs never did, which is how it slipped.
RSpec.describe "Browsing with a session cookie", type: :request do
  # Test env disables CSRF protection, so pages never write a session and no cookie
  # comes back. Turn it on here to behave like development/production.
  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  it "keeps working after the session cookie is set" do
    get root_path
    expect(response).to have_http_status(:ok)
    expect(response.headers["Set-Cookie"]).to be_present

    %w[/applications /reviews /sync /applications/new /].each do |path|
      get path
      expect(response).to have_http_status(:ok), "#{path} returned #{response.status}"
    end
  end

  it "shows the flash after a redirect (read from the session)" do
    get new_application_path
    token = response.body[/name="authenticity_token" value="([^"]+)"/, 1]
    post applications_path, params: { authenticity_token: token,
                                      application: { company_name: "Initech", applied_on: Date.current.iso8601 } }
    follow_redirect!

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Added Initech.")
  end
end
