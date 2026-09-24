# Exploratory script: authenticate to Gmail (read-only), search for job-application
# emails, print a summary, and dump the first 30 messages to sample_emails.json.

require "json"
require "socket"
require "uri"
require "time"
require "googleauth"
require "googleauth/stores/file_token_store"
require "google/apis/gmail_v1"

CREDENTIALS_PATH = "credentials.json"
TOKEN_PATH       = "token.yaml"
OUTPUT_PATH      = "sample_emails.json"
SCOPE            = Google::Apis::GmailV1::AUTH_GMAIL_READONLY
USER_ID          = "default"
# A "web" OAuth client needs this exact URI registered as an authorized redirect URI.
# A "Desktop app" client accepts any localhost port.
REDIRECT_PORT    = 8080
REDIRECT_URI     = "http://localhost:#{REDIRECT_PORT}/"
SAMPLE_SIZE      = 30

QUERY = 'newer_than:180d (subject:(application OR applied OR candidacy OR ' \
        '"thank you for your interest" OR interview) OR from:(greenhouse.io OR ' \
        'lever.co OR myworkdayjobs.com OR ashbyhq.com OR naukri.com OR ' \
        'jobs-noreply@linkedin.com))'

def open_browser(url)
  if Gem.win_platform?
    system("rundll32", "url.dll,FileProtocolHandler", url)
  elsif RUBY_PLATFORM.include?("darwin")
    system("open", url)
  else
    system("xdg-open", url, out: File::NULL, err: File::NULL)
  end
end

# Start a one-shot HTTP server on localhost and return the `code` query param
# from the OAuth redirect.
def wait_for_auth_code(server)
  loop do
    client = server.accept
    request_line = client.gets.to_s
    # Drain the request headers.
    while (line = client.gets) && line != "\r\n"; end

    path = request_line.split(" ")[1].to_s
    params = URI.decode_www_form(URI(path).query.to_s).to_h

    body =
      if params["code"]
        "Authorization complete. You can close this tab and return to the terminal."
      elsif params["error"]
        "Authorization failed: #{params['error']}"
      end

    if body.nil?
      # e.g. /favicon.ico — ignore and keep waiting.
      client.print "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
      client.close
      next
    end

    client.print "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\n" \
                 "Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
    client.close

    abort "OAuth error: #{params['error']}" if params["error"]
    return params["code"]
  end
end

def authorize
  client_id   = Google::Auth::ClientId.from_file(CREDENTIALS_PATH)
  token_store = Google::Auth::Stores::FileTokenStore.new(file: TOKEN_PATH)
  authorizer  = Google::Auth::UserAuthorizer.new(client_id, SCOPE, token_store, REDIRECT_URI)

  credentials = authorizer.get_credentials(USER_ID)
  return credentials if credentials

  server = TCPServer.new("127.0.0.1", REDIRECT_PORT)
  begin
    url = authorizer.get_authorization_url(base_url: REDIRECT_URI)
    puts "Opening your browser to authorize read-only Gmail access."
    puts "If it doesn't open, visit this URL manually:\n\n#{url}\n\n"
    open_browser(url)

    code = wait_for_auth_code(server)
  ensure
    server.close
  end

  authorizer.get_and_store_credentials_from_code(
    user_id: USER_ID, code: code, base_url: REDIRECT_URI
  )
end

def header(message, name)
  message.payload&.headers&.find { |h| h.name.casecmp?(name) }&.value.to_s
end

def decode_part(part)
  data = part.body&.data
  return "" if data.nil? || data.empty?

  charset = part.headers&.find { |h| h.name.casecmp?("Content-Type") }
                &.value.to_s[/charset="?([^";\s]+)/i, 1] || "UTF-8"
  text = data.dup
  begin
    text.force_encoding(charset)
  rescue ArgumentError
    text.force_encoding("UTF-8")
  end
  text.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
end

# Walk the MIME tree collecting parts of the given mime type.
def collect_parts(part, mime_type, acc = [])
  return acc if part.nil?

  if part.mime_type == mime_type && (part.filename.nil? || part.filename.empty?)
    acc << part
  end
  (part.parts || []).each { |p| collect_parts(p, mime_type, acc) }
  acc
end

def plain_text_body(message)
  plain = collect_parts(message.payload, "text/plain")
  return plain.map { |p| decode_part(p) }.join("\n").strip unless plain.empty?

  # Fall back to crudely stripped HTML when there's no text/plain part.
  html = collect_parts(message.payload, "text/html").map { |p| decode_part(p) }.join("\n")
  html.gsub(%r{<(script|style)[^>]*>.*?</\1>}mi, " ")
      .gsub(/<br\s*\/?>|<\/p>|<\/div>|<\/tr>/i, "\n")
      .gsub(/<[^>]+>/, " ")
      .gsub("&nbsp;", " ").gsub("&amp;", "&").gsub("&lt;", "<").gsub("&gt;", ">")
      .gsub("&quot;", '"').gsub("&#39;", "'")
      .gsub(/[ \t]+/, " ").gsub(/\n\s*\n+/, "\n\n").strip
end

def message_date(message)
  Time.at(message.internal_date.to_i / 1000).localtime
end

gmail = Google::Apis::GmailV1::GmailService.new
gmail.client_options.application_name = "job-tracker-explore"
gmail.authorization = authorize

# Page through every match to get an exact count (result_size_estimate is only an estimate).
ids = []
page_token = nil
loop do
  resp = gmail.list_user_messages("me", q: QUERY, max_results: 500, page_token: page_token)
  ids.concat((resp.messages || []).map(&:id))
  page_token = resp.next_page_token
  break if page_token.nil?
end

puts "Total matches: #{ids.size}"
puts

samples = ids.first(SAMPLE_SIZE).map do |id|
  msg = gmail.get_user_message("me", id, format: "full")
  date    = message_date(msg)
  from    = header(msg, "From")
  subject = header(msg, "Subject")

  puts "#{date.strftime('%Y-%m-%d %H:%M')} | #{from} | #{subject}"

  {
    id: msg.id,
    thread_id: msg.thread_id,
    date: date.iso8601,
    from: from,
    subject: subject,
    snippet: msg.snippet,
    body: plain_text_body(msg)
  }
end

File.write(OUTPUT_PATH, JSON.pretty_generate(samples))
puts
puts "Wrote #{samples.size} messages to #{OUTPUT_PATH}"
