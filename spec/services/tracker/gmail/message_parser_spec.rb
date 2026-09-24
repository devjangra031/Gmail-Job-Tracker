require "rails_helper"

RSpec.describe Tracker::Gmail::MessageParser do
  def part(mime_type, data = nil, charset: "UTF-8", filename: "", parts: nil)
    Google::Apis::GmailV1::MessagePart.new(
      mime_type: mime_type, filename: filename, parts: parts,
      headers: [ Google::Apis::GmailV1::MessagePartHeader.new(name: "Content-Type", value: "#{mime_type}; charset=#{charset}") ],
      body: Google::Apis::GmailV1::MessagePartBody.new(data: data)
    )
  end

  def message(payload, labels: [ "INBOX" ], snippet: "Snippet &amp; more")
    payload.headers = [
      Google::Apis::GmailV1::MessagePartHeader.new(name: "From", value: "Neha <neha@kestrelsoft.com>"),
      Google::Apis::GmailV1::MessagePartHeader.new(name: "Subject", value: "L1 Interview | ALEX | Backend Engineer")
    ] + Array(payload.headers)
    Google::Apis::GmailV1::Message.new(id: "m1", thread_id: "t1", label_ids: labels, snippet: snippet,
                   internal_date: Time.zone.parse("2026-09-22 10:58").to_i * 1000, payload: payload)
  end

  it "reads headers, time, snippet and thread" do
    attrs = described_class.call(message(part("text/plain", "Hello there, your interview is confirmed for Tuesday.")))

    expect(attrs).to include(gmail_message_id: "m1", thread_id: "t1", subject: "L1 Interview | ALEX | Backend Engineer",
                             from_address: "Neha <neha@kestrelsoft.com>", raw_snippet: "Snippet & more", outgoing: false)
    expect(attrs[:sent_at]).to eq(Time.zone.parse("2026-09-22 10:58"))
  end

  it "prefers text/plain in a multipart/alternative message" do
    payload = part("multipart/alternative", parts: [
      part("text/plain", "Plain version of the interview confirmation, long enough to count."),
      part("text/html", "<p>HTML version</p>")
    ])

    expect(described_class.call(message(payload))[:body]).to eq("Plain version of the interview confirmation, long enough to count.")
  end

  it "finds text/plain nested in multipart/mixed with attachments, ignoring the attachment" do
    payload = part("multipart/mixed", parts: [
      part("multipart/alternative", parts: [ part("text/plain", "Nested plain body that is long enough to use."),
                                             part("text/html", "<b>html</b>") ]),
      part("text/plain", "attachment text", filename: "notes.txt")
    ])

    expect(described_class.call(message(payload))[:body]).to eq("Nested plain body that is long enough to use.")
  end

  it "falls back to HTML when the plain part is a stub like 'Please Enable HTML'" do
    payload = part("multipart/alternative", parts: [
      part("text/plain", "Please Enable HTML"),
      part("text/html", "<html><head><style>p{color:red}</style></head><body><p>Application Confirmed</p>" \
                        "<div>Applied Position: Engineering Manager</div><script>x()</script></body></html>")
    ])

    body = described_class.call(message(payload))[:body]

    expect(body).to eq("Application Confirmed\nApplied Position: Engineering Manager")
  end

  it "strips HTML-only messages to text with entities decoded" do
    body = described_class.call(message(part("text/html", "<p>Thank you&nbsp;for applying to Quanta &amp; co.</p>")))[:body]

    expect(body).to eq("Thank you for applying to Quanta & co.")
  end

  it "decodes non-UTF-8 charsets" do
    latin1 = "Résumé received for the Backend Engineer role at Kestrel.".encode("ISO-8859-1").b

    expect(described_class.call(message(part("text/plain", latin1, charset: "ISO-8859-1")))[:body])
      .to eq("Résumé received for the Backend Engineer role at Kestrel.")
  end

  it "drops URLs from the stored body but keeps LinkedIn's email type" do
    text = "Your update from Tessellate https://www.linkedin.com/help?lipi=urn%3Ali%3Apage%3Aemail_email_jobs_application_rejected_01%3Babc\n\n\n\nThanks"

    attrs = described_class.call(message(part("text/plain", text)))

    expect(attrs[:linkedin_type]).to eq("jobs_application_rejected")
    expect(attrs[:body]).to eq("Your update from Tessellate\n\nThanks")
  end

  it "truncates to 1500 characters" do
    expect(described_class.call(message(part("text/plain", "word " * 1000)))[:body].length).to eq(1500)
  end

  it "marks mail you sent as outgoing" do
    expect(described_class.call(message(part("text/plain", "Hi, sharing my CV for the role."), labels: [ "SENT" ]))[:outgoing]).to be(true)
  end
end
