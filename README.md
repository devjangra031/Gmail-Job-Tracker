# Job Tracker

A personal job-application tracker that builds itself from your Gmail.

It reads job-related email (read-only), uses an LLM on Groq to work out what each
email means (applied, shortlisted, interview, rejection, offer…), groups emails
into one application per company and role, and follows each application through
its interview rounds. A dashboard shows who replied, who rejected you, who went
quiet, and how long replies take.

It runs **locally on your machine** (built and tested on Windows) as a Rails 8
app with SQLite. It's single-user and has no login.

```
Applied 11 Sep → R1 AI assessment 13 Sep → R2 Round 2 17 Sep ↻1 → Rejected 20 Sep
```

---

## Contents

1. [What it does (and doesn't)](#what-it-does-and-doesnt)
2. [How it works](#how-it-works)
3. [Requirements](#requirements)
4. [Setup, step by step](#setup-step-by-step)
5. [Using the app](#using-the-app)
6. [Configuration reference](#configuration-reference)
7. [Rake tasks](#rake-tasks)
8. [Limits, quotas and cost](#limits-quotas-and-cost)
9. [Troubleshooting](#troubleshooting)
10. [Privacy and files that must never be committed](#privacy-and-files-that-must-never-be-committed)
11. [Development](#development)

---

## What it does (and doesn't)

**It does:**
- Search Gmail for job-related mail in a date range you choose (default: last 60 days).
- Keep only mail about applications you actually made. Job suggestions ("X is
  hiring", "jobs similar to…", alerts, recruiter-viewed-your-profile, marketing)
  are filtered out.
- Classify each email with an LLM, or with free built-in rules for formulaic
  mail (LinkedIn and Cutshort notifications).
- Group emails into applications and work out the status and round number from
  the timeline, including reschedules, calendar reminders and repeated invites.
- Show a dashboard with a funnel, response, rejection and ghost rates, reply
  times, charts per week and month, per-company journeys, per-source response
  rates, and upcoming interviews.
- Let you correct things: a review queue for uncertain emails, adding
  applications by hand, and adding updates that didn't come by email (a
  rejection on a call, an interview set up on WhatsApp).

**It doesn't:**
- Send, modify, label or delete anything in Gmail. It only requests the
  `gmail.readonly` permission.
- Run in the cloud or share data with anyone. Everything is stored in a local
  SQLite file. The only thing that leaves your machine is the text of each email
  sent to Groq for classification (see [Privacy](#privacy-and-files-that-must-never-be-committed)).

---

## How it works

```
Gmail (read-only)
   │  search: config/tracker.yml → gmail_query + your date range
   ▼
Fetch new messages ── skipped if already stored; rate-limited; retries on quota errors
   │
   ▼
Classify each email (oldest first)
   ├─ job suggestion / marketing?  → filtered locally (free)
   ├─ LinkedIn / Cutshort formula? → read by rules (free)
   └─ anything else                → Groq LLM (JSON: category, company, role, round, date…)
   │
   ▼
Group into applications ── same Gmail thread, else same company + role
   │
   ▼
Infer status and rounds from the event timeline ── recomputable at any time
   │
   ▼
Dashboard · Applications list · Journey per application · Review queue
```

Emails are the source of truth. Applications, rounds and statuses are always
derived from them, so improving a rule and running `bin/rails tracker:recompute`
fixes old data too.

---

## Requirements

| What | Version / notes |
|---|---|
| Ruby | **3.4.10** (see `.ruby-version`). On Windows use **RubyInstaller "Ruby+Devkit"**. |
| Bundler | Comes with Ruby. |
| Git | Any recent version. |
| A Google account | The Gmail inbox you want to track. |
| A Google Cloud project | Free. Needed to let the app read Gmail (steps below). |
| A Groq account | Free tier works. Needed for the LLM (steps below). |

You don't need Node.js, Redis, Docker or a separate database server.

---

## Setup, step by step

Do these in order. Commands assume you are in the project folder. PowerShell
and Git Bash both work.

### Step 1: Install Ruby

**Windows**
1. Download **Ruby+Devkit 3.4.x (x64)** from <https://rubyinstaller.org/downloads/>.
2. Run the installer and keep "Run `ridk install`" ticked at the end. When the
   console asks, choose option **3** (MSYS2 and MINGW development toolchain).
3. Open a **new** terminal and check the version:
   ```
   ruby -v
   ```
   It should print `ruby 3.4.x`.

**macOS / Linux**: install Ruby 3.4.10 with your usual version manager
(`rbenv`, `asdf`, `mise`…).

### Step 2: Get the code and install gems

```
git clone <this repository's URL> job-tracker
cd job-tracker
bundle install
```

### Step 3: Set up Google Cloud (so the app can read Gmail)

This creates the OAuth client the app uses to ask for read-only Gmail access.
You do it once, and it's free.

1. **Create a project.**
   Go to <https://console.cloud.google.com/>, open the project picker at the top,
   click **New project**, name it (e.g. `job-tracker`) and create it. Make sure
   it's selected.

2. **Enable the Gmail API.**
   Go to **APIs & Services → Library**, search for **Gmail API**, open it and click
   **Enable**.

3. **Configure the consent screen.**
   Go to **APIs & Services → OAuth consent screen**. Newer consoles call it
   **Google Auth Platform**, with the sections *Branding*, *Audience*, *Data access*
   and *Clients*.
   - **App name:** anything, e.g. `Job Tracker`.
   - **User support email** and **developer contact email:** your email.
   - **Audience / user type:** **External**.
   - **Publishing status:** leave it in **Testing**. Don't publish it.
   - **Test users:** click **Add users** and add **the Gmail address you want to
     track**. In Testing mode, only listed test users can sign in.
   - **Scopes / Data access:** click **Add or remove scopes** and add
     `https://www.googleapis.com/auth/gmail.readonly` (shown as
     "View your email messages and settings"). Save.

4. **Create the OAuth client.**
   Go to **APIs & Services → Credentials** (or **Clients**) → **Create credentials
   → OAuth client ID**.
   - **Application type:** **Web application**.
   - **Name:** anything.
   - **Authorized redirect URIs:** click **Add URI** and enter exactly
     ```
     http://localhost:8080/
     ```
     Include `http`, `localhost`, port `8080` and the trailing slash. If you
     change `gmail_redirect_port` in `config/tracker.yml`, use that port here
     instead.
   - Leave *Authorized JavaScript origins* empty and click **Create**.

5. **Download the credentials.**
   In the dialog that appears (or from the client's page), click **Download JSON**.
   Rename the file to **`credentials.json`** and put it in the **project root**, next
   to `Gemfile`:
   ```
   job-tracker/
   ├── credentials.json   ← here
   ├── Gemfile
   └── ...
   ```
   It's gitignored. Never commit or share it.

> **About Testing mode:** Google expires the login for Testing-mode apps after
> about **7 days**. When that happens, the Sync page shows **Reconnect Gmail**.
> Click it and sign in again. Nothing else is needed.

### Step 4: Get a Groq API key

1. Sign in at <https://console.groq.com/>.
2. Go to **API Keys** → **Create API Key**, give it a name, and copy the key
   (it starts with `gsk_`). You won't be able to see it again.

### Step 5: Create your `.env` file

Copy the template:

```
# PowerShell
Copy-Item .env.example .env
# Git Bash / macOS / Linux
cp .env.example .env
```

Open `.env` and fill it in:

| Variable | Required | What to put |
|---|---|---|
| `GROQ_API_KEY` | **Yes** | The key from step 4, e.g. `GROQ_API_KEY=gsk_abc123…` |
| `MY_EMAIL_ADDRESSES` | No | Your own address(es), comma-separated. Only used when importing `sample_emails.json` (see [Optional: test on a sample first](#optional-test-on-a-sample-first)). Synced mail uses Gmail's *Sent* label instead. |

`.env` is gitignored. Never commit it.

### Step 6: Check that the Groq model is available

Groq retires models regularly. List what it serves right now:

```
bin/rails tracker:models
```

The configured model (`groq_model` in `config/tracker.yml`) is marked
`<- configured`. If the output says it's **NOT available**, pick another model ID
from the list and set it in `config/tracker.yml`. If the new model isn't a
reasoning model (i.e. not gpt-oss or qwen3), also set `groq_reasoning_effort: null`.

This is also a good test that your API key works.

### Step 7: Create the database and build the CSS

```
bin/rails db:prepare
bin/rails tailwindcss:build
```

`db:prepare` creates `storage/development.sqlite3` and all tables. It starts
empty. To explore with made-up demo data first, run `DEMO=1 bin/rails db:seed`
(PowerShell: `$env:DEMO=1; bin/rails db:seed`), and remove it later with
`bin/rails tracker:remove_demo_data`.

### Step 8: Start the app

```
bin/rails server
```

Open <http://localhost:3000>. Keep this terminal open while you use the app.

> `bin/dev` (server and CSS watcher together) depends on `foreman`, which is
> unreliable on Windows. If you change views or CSS classes, run
> `bin/rails tailwindcss:watch` in a second terminal instead.

### Step 9: Connect Gmail

1. In the app, open **Sync** (top navigation). It will say *Gmail is not connected*.
2. Click **Reconnect Gmail**. A Google sign-in page opens.
3. Choose the Gmail account you added as a **test user** in step 3.
4. Google warns **"Google hasn't verified this app"**. That's expected for your
   own Testing-mode app. Click **Continue** (on some screens it's under
   **Advanced → Go to Job Tracker (unsafe)**).
5. Allow **read-only** access to your email.
6. You're sent back to the Sync page, which now shows **● Gmail connected
   (read-only)**. The login is saved to `token.yaml` in the project root and
   reused from then on.

If it doesn't come back, see [Troubleshooting](#troubleshooting). The usual
causes are a redirect URI mismatch or port 8080 already being in use.

### Step 10: Run your first sync

1. On the **Sync** page, keep the default range (last 60 days) or pick your own.
2. Click **Sync new mail**. A progress bar shows two phases:
   - **Fetching new mail from Gmail.** This is rate-limited to 5 requests per
     second, so roughly 1–2 minutes per 500 emails.
   - **Classifying.** Job suggestions and LinkedIn/Cutshort notifications are
     handled instantly and for free. The rest go to Groq one at a time. On the
     free tier, expect a few emails per minute.
3. You can browse the app while it runs. Results appear as each email is done.

**If it stops early** (Groq's daily limit, an expired Gmail login, a closed
server), everything done so far is kept. Click **Sync new mail** again later:
mail already fetched is skipped, and anything left unclassified is picked up.
Syncing the same range twice costs nothing extra.

### Step 11: Tidy up

- Open **Review** (with a count badge in the navigation) and go through the emails
  the model wasn't sure about. Pick the right category, fix the company or role,
  or discard as noise.
- Use **+ Add application** for applications with no email behind them.
- On any application's page, use **Add an update** for news that came by phone,
  WhatsApp or in person.

You're set up. From now on, start the server (step 8) and click **Sync new mail**
whenever you want fresh data.

### Optional: test on a sample first

To check classification accuracy before syncing your whole inbox:

```
ruby explore.rb                          # signs in to Gmail, writes sample_emails.json (30 emails)
bin/rails tracker:classify_sample LIMIT=5   # classify a few with Groq and print the results
bin/rails tracker:classify_sample           # the rest (resumable); FORCE=1 redoes all
```

If you also create `db/seeds/sample_labels.yml` (the expected answer for each
message ID), the task scores the model against it and lists mismatches. Both
files contain your personal mail and are gitignored.

---

## Using the app

| Page | What it's for |
|---|---|
| **Dashboard** (`/`) | Cards (applied, awaiting reply, in progress, ghosted, rejected, offers), the funnel with drop-off, response, rejection and ghost rates, median and p90 days to first reply, median days to rejection, upcoming interviews, applications and rejections per week and month (each chart has a table view), **By company** (one line per application with its dated journey), and **By source** (reply rate per job board / ATS). |
| **Applications** | Every application with its journey. Sort by any column. Filter by search text, status, source and applied date (last 7/30/60/90 days or custom). Filters apply instantly and only look at **stored** data; they never fetch mail. |
| **Application page** | The journey, the full timeline grouped by round (reschedules shown under their round), links to every source email, and **Add an update** for news that didn't come by email. |
| **Review** | Emails the model was unsure about (confidence below 0.7) or couldn't read. They don't count anywhere until you confirm or discard them. |
| **Sync** | Gmail connection status, the date range, the **Sync new mail** button, live progress and recent syncs. This is the only page that fetches new mail. |
| **+ Add application** | For applications with no email (referrals, portals that don't email). Later emails for the same company and role join it automatically. |

### What the statuses mean

| Status | Meaning |
|---|---|
| **Awaiting reply** | You applied; nothing back from the company yet. |
| **In progress** | The company replied: shortlisted, recruiter contact, AI screen, assessment or interview. |
| **Ghosted** | Not finished, and nothing from the company for **30+ days** (`ghost_after_days`), whether they never replied or went quiet after an interview. Your own follow-up emails don't reset this clock. |
| **Rejected / Offer / Withdrawn** | Finished. |

A **reply** is anything from the company after applying. "Your application was
viewed" notifications don't count.

### How rounds are numbered

- Applying is round 0. AI screens, assessments and interviews each get their own
  round, in order.
- A reschedule, a confirmation, a calendar reminder, or the same "L1 interview"
  invite sent again stays in the **same round**. A changed time is counted as a
  reschedule (↻).
- An email that names its round ("Round 2", "L2") uses that number. The numbering
  never goes backwards.
- Rejections, offers and withdrawals end the application but don't use up a round.

The full rules are at the top of `app/services/applications/infer_status.rb`.

---

## Configuration reference

### `.env` (secrets, gitignored)

| Variable | Required | Purpose |
|---|---|---|
| `GROQ_API_KEY` | Yes | Groq API key used for classification. |
| `MY_EMAIL_ADDRESSES` | No | Marks your own mail as outgoing when importing `sample_emails.json`. |

### `config/tracker.yml` (settings, committed)

**Restart the server after editing this file.**

| Key | Default | What it does |
|---|---|---|
| `gmail_query` | job subjects + ATS/job-board senders, minus alert senders | The Gmail search. The date range is added as `after:`/`before:` at sync time. Add a sender here if its mail isn't being picked up. |
| `gmail_redirect_port` | `8080` | Port for the Gmail sign-in redirect. Must match the redirect URI in Google Cloud (`http://localhost:PORT/`). |
| `gmail_max_retries` | `5` | Retries for Gmail 429 / 5xx / quota errors, with exponential backoff. |
| `gmail_requests_per_second` | `5` | Client-side rate limit for Gmail requests. |
| `default_sync_days` | `60` | Default start of the Sync date range. |
| `noise_senders` | alert senders | Sender addresses whose mail is always a suggestion or marketing. Filtered locally, never sent to Groq. |
| `noise_subject_phrases` | "is hiring", "jobs similar to"… | Subject phrases that only appear on suggestions. |
| `time_zone` | `Asia/Kolkata` | Used for display, for date ranges, and for interview times that don't name a zone. |
| `groq_model` | see file | Groq model ID. Check it with `bin/rails tracker:models`. |
| `groq_reasoning_effort` | `low` | Only for reasoning models (gpt-oss, qwen3); set to `null` for others. |
| `groq_delay_seconds` | `2` | Pause between Groq calls. |
| `groq_max_retries` | `5` | Retries for Groq 429 / 5xx. |
| `groq_max_wait_seconds` | `120` | If Groq asks to wait longer than this (usually a daily limit), stop the sync cleanly instead. |
| `review_threshold` | `0.7` | Classifications below this confidence go to the Review queue. |
| `ghost_after_days` | `30` | Days of silence before an unfinished application counts as ghosted. |
| `ats_domains` | Greenhouse, Lever, Workday, LinkedIn, Naukri, Cutshort… | Job boards and ATSs. Used as the application's **source**, and never mistaken for the employer. |
| `personal_domains` | gmail.com, outlook.com… | Never used to guess a company name. |

### Common changes

- **A job board's mail isn't showing up:** add its domain to the `from:(...)`
  part of `gmail_query`, and to `ats_domains`. Restart, then sync again.
- **Suggestions or marketing are getting through:** add the sender to
  `noise_senders`, or a phrase to `noise_subject_phrases`. Restart, then run
  `bin/rails tracker:reapply_rules` to clean up mail you already have (free, no
  Groq calls).
- **Changing the model:** run `bin/rails tracker:models`, set `groq_model`,
  and restart.

---

## Rake tasks

| Task | What it does | Calls Groq? |
|---|---|---|
| `bin/rails tracker:models` | Lists Groq's current model IDs and flags whether yours is available. | Lists models only |
| `bin/rails tracker:reapply_rules` | Re-applies the free local rules (suggestion filter, LinkedIn/Cutshort rules) to mail already classified. Never overrides your Review decisions. | No |
| `bin/rails tracker:recompute` | Rebuilds every application's events, rounds and status from its emails. Safe to run any time; IDs stay the same. | No |
| `bin/rails tracker:regroup` | Regroups all emails into applications from scratch (after changing company or role normalization). IDs change. Manual applications and updates you added by hand are kept. | No |
| `bin/rails tracker:classify_sample` | Classifies `sample_emails.json` and prints an accuracy report. `LIMIT=n`, `FORCE=1`. | Yes |
| `bin/rails tracker:remove_demo_data` | Removes the made-up demo companies. Your real mail is untouched. | No |

**Start completely fresh** (deletes all synced data but keeps your Gmail login).
Stop the server first, then:

```
bin/rails db:drop db:create db:migrate
```

---

## Limits, quotas and cost

- **Gmail API:** free. Google limits requests per minute per user. The app stays
  well under the limit (`gmail_requests_per_second`), and if Google still pushes
  back ("Quota exceeded … per minute per user") it waits and retries.
- **Groq:** the free tier limits tokens per minute and per day, and the limits
  differ by model. See <https://console.groq.com/settings/limits>. Each
  classified email costs roughly 2,000 tokens, mostly the fixed instructions. To
  save tokens:
  - Job suggestions and marketing are filtered before Groq (free).
  - LinkedIn "application sent / rejected / viewed" and Cutshort "shortlisted"
    emails are read by rules (free). That's typically 40–60% of all mail.
  - Emails are never classified twice.
  - When a daily limit is reached, the sync stops with a clear message and resumes
    on the next sync.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Google shows **`redirect_uri_mismatch`** | The OAuth client's *Authorized redirect URIs* must contain exactly `http://localhost:8080/` (with the trailing slash), and the client type must be **Web application**. Changes can take a few minutes to apply. |
| **"Access blocked: … has not completed the Google verification process"** | Your Gmail address isn't a **test user**. Add it under OAuth consent screen → Audience → Test users. |
| **"Google hasn't verified this app"** | Expected. Click **Continue**, or **Advanced → Go to … (unsafe)**. |
| **"Port 8080 is busy"** on Reconnect | An earlier Reconnect is still waiting (finish it in the Google tab, or wait up to 5 minutes), or `explore.rb` is running. |
| Sync page says **Gmail access expired** | Normal after about 7 days in Testing mode. Click **Reconnect Gmail**, then sync again. |
| **`credentials.json is missing`** | Put the downloaded OAuth JSON in the project root, named exactly `credentials.json`. |
| Sync stops with **"GROQ_API_KEY is not set"** or **"rejected the API key"** | Check `.env` (the variable name, no quotes, no spaces), then restart the server. |
| Sync stops with **"Groq model … is unavailable"** | Groq retired the model. Run `bin/rails tracker:models`, update `groq_model`, and restart. |
| Sync stops with **"rate limit reached … per day"** | The Groq free daily limit. Everything so far is saved; sync again later (usually the next day) to continue. |
| Sync shows **"Interrupted"** | The server was stopped mid-sync. Sync again; it resumes. |
| **`Permission denied … development.sqlite3`** on `db:drop` / `db:reset` | A server or console still has the database open. Stop every `rails server` / `rails console` (Ctrl+C), then retry. On Windows, `Get-Process ruby` lists them. |
| A page shows **"Migrations are pending"** | Run `bin/rails db:migrate`. |
| The page has no styling | Run `bin/rails tailwindcss:build` (or keep `tailwindcss:watch` running). |
| One company shows up as two applications | Emails in the same Gmail thread always join together, and names are normalized ("Acme Technologies Pvt. Ltd." = "Acme"). Two genuinely different spellings (e.g. "Acme" vs "AcmeCorp") aren't merged automatically, and there's no merge button yet. That needs a normalization change followed by `bin/rails tracker:regroup`. |
| The wrong company is shown | If the email is in **Review**, correct the company there. For confidently classified mail there's no edit screen yet. |
| A company's mail isn't showing up at all | Its sender or subject isn't matched by `gmail_query`. See [Common changes](#common-changes). |

---

## Privacy and files that must never be committed

- **Stays on your machine:** the SQLite database (`storage/*.sqlite3`), your
  Gmail login (`token.yaml`) and your OAuth client (`credentials.json`).
- **Sent to Groq:** the sender, subject, date and up to 1,500 characters of the
  body of each email that isn't filtered or handled by a rule, so it can be
  classified. Nothing else is sent anywhere.
- **Gmail access is read-only.** The app can't send, change or delete mail. You
  can revoke access any time at <https://myaccount.google.com/permissions>.

These are gitignored. Keep them that way:

| File | Contains |
|---|---|
| `credentials.json` | Your Google OAuth client secret |
| `token.yaml` | Your Gmail login (refresh token) |
| `.env` | Your Groq API key |
| `storage/*.sqlite3` | All your synced mail and applications |
| `sample_emails.json`, `db/seeds/sample_labels.yml` | Real emails from your inbox |
| `config/master.key` | Rails credentials key |

`.env.example` **is** committed. It's the empty template.

---

## Development

```
bundle exec rspec     # tests: WebMock blocks all real HTTP, so Gmail and Groq are never called
bin/rubocop           # lint
```

**Stack:** Rails 8.1, Ruby 3.4, SQLite, Hotwire (Turbo + Stimulus), importmap,
Tailwind, Chartkick, google-apis-gmail_v1 + googleauth, ruby-openai (pointed at
Groq), RSpec + WebMock.

**Where things live**

| Path | What |
|---|---|
| `app/services/tracker/gmail/` | Gmail sign-in (loopback redirect), API client (rate limit, retries), message parsing (plain text preferred, HTML fallback, 1,500 characters) |
| `app/services/tracker/sync.rb` | The background sync: fetch, then classify, with live progress |
| `app/services/tracker/noise_filter.rb` | Local job-suggestion and marketing filter |
| `app/services/tracker/rule_classifier.rb` | Free rules for LinkedIn and Cutshort notifications |
| `app/services/tracker/classifier*` | Provider-independent prompt, JSON validation, retry on invalid JSON |
| `app/services/tracker/providers/groq.rb` | **All** Groq-specific code. To switch provider, write a class with the same `complete` / `models` methods and return it from `Tracker::Providers.default`. |
| `app/services/applications/` | Grouping (`assign_email`), rebuilding (`rebuild`), round and status inference (`infer_status`), filters, manual additions |
| `app/services/tracker/analytics.rb` | Dashboard numbers, computed in Ruby |
| `config/tracker.yml` | All tunable settings |

**Design notes**
- **Background work is a plain Ruby thread** inside the server process, not Solid
  Queue or Sidekiq, because Solid Queue's forking supervisor doesn't work on
  Windows. In development, code reloads wait until a running sync finishes.
- **Charts group data by week and month in Ruby.** Groupdate doesn't support SQLite.
- **The `json` gem is pinned below 3.** json 3.0 breaks how Rails 8.1.3 reads the
  session cookie. Remove the pin in the `Gemfile` once Rails supports json 3.
- **Status is never stored as the source of truth.** It's always derived from the
  email timeline, plus any updates you added by hand.
