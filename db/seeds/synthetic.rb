# Made-up applications (fictional companies) exercising every inference path.
# Dates are relative to now so ghosting and "upcoming" look realistic.

module SyntheticSeeds
  module_function

  def now
    @now ||= Time.current.change(min: 0)
  end

  def email(id, thread, days_ago, category, company:, role: nil, from:, subject:, body:, **extra)
    record = Email.find_or_initialize_by(gmail_message_id: "seed-#{id}")
    record.assign_attributes(
      thread_id: "seed-thread-#{thread}",
      sent_at: now - days_ago.days,
      from_address: from,
      from_domain: nil,
      subject: subject,
      body: body,
      raw_snippet: body.truncate(120),
      category: category,
      extracted_company: company,
      extracted_role: role,
      round_label: nil,
      round_hint: nil,
      is_reschedule: false,
      scheduled_at: nil,
      confidence: 0.95,
      classifier_reason: "seed data",
      classifier_model: "seed",
      classified_at: now,
      needs_review: false,
      review_state: nil,
      **extra
    )
    record.save!
    record
  end
end

s = SyntheticSeeds
gh = "no-reply@us.greenhouse-mail.io"

emails = [
  # Acme Payments: AI screen, round 1 rescheduled in-thread, "Round 2" (our round 3), rejection.
  s.email(1, "acme-1", 62, "applied", company: "Acme Payments Inc.", role: "Backend Engineer", from: "Acme Payments <#{gh}>",
          subject: "Thank you for applying to Acme Payments",
          body: "Hi, thanks for applying for the Backend Engineer role at Acme Payments. Our team will review your application."),
  s.email(2, "acme-2", 58, "ai_screen", company: "Acme Payments", role: "Backend Engineer", from: "Acme Payments <#{gh}>",
          subject: "Next step: AI screening interview", round_label: "AI screening",
          body: "Please complete a 20-minute AI-led screening interview within 5 days using the link below."),
  s.email(3, "acme-3", 50, "interview_scheduled", company: "Acme Payments", role: "Backend Engineer",
          from: "Priya (Acme Payments) <priya@acmepayments.com>", subject: "Interview invitation: Technical round",
          round_label: "technical round", scheduled_at: s.now - 47.days,
          body: "We'd like to invite you to a 60-minute technical interview on the date below."),
  s.email(4, "acme-3", 49, "interview_scheduled", company: "Acme Payments", role: "Backend Engineer",
          from: "Priya (Acme Payments) <priya@acmepayments.com>", subject: "RE: Interview invitation: Technical round",
          is_reschedule: true, scheduled_at: s.now - 45.days,
          body: "Our interviewer is unavailable, so we've moved your technical interview two days later."),
  s.email(5, "acme-4", 40, "interview_scheduled", company: "Acme Payments", role: "Backend Engineer",
          from: "Priya (Acme Payments) <priya@acmepayments.com>", subject: "Round 2 interview - system design",
          round_hint: 2, round_label: "Round 2 - system design", scheduled_at: s.now - 37.days,
          body: "Congratulations on clearing round 1! Your round 2 system design interview is scheduled."),
  s.email(6, "acme-4", 30, "rejection", company: "Acme Payments", role: "Backend Engineer",
          from: "Priya (Acme Payments) <priya@acmepayments.com>", subject: "RE: Round 2 interview - system design",
          body: "Thank you for your time. Unfortunately we have decided not to move forward with your candidacy."),

  # Globex: assessment, two interviews, offer.
  s.email(7, "globex-1", 45, "applied", company: "Globex Corporation", role: "Data Engineer", from: "Globex <no-reply@hire.lever.co>",
          subject: "Globex - application received", body: "We've received your application for Data Engineer."),
  s.email(8, "globex-2", 40, "assessment", company: "Globex", role: "Data Engineer", from: "Globex <no-reply@hire.lever.co>",
          subject: "Online assessment for Data Engineer", round_label: "online assessment",
          body: "Please complete the 90-minute SQL and Python assessment on HackerRank within 72 hours."),
  s.email(9, "globex-3", 30, "interview_scheduled", company: "Globex", role: "Data Engineer", from: "Sam at Globex <sam@globex.com>",
          subject: "Interview confirmed", round_label: "technical round", scheduled_at: s.now - 28.days,
          body: "Your technical interview with the data platform team is confirmed."),
  s.email(10, "globex-3", 27, "interview_completed", company: "Globex", role: "Data Engineer", from: "Sam at Globex <sam@globex.com>",
          subject: "RE: Interview confirmed", body: "Thanks for speaking with the team yesterday. We'll be in touch with next steps."),
  s.email(11, "globex-4", 20, "interview_scheduled", company: "Globex", role: "Data Engineer", from: "Sam at Globex <sam@globex.com>",
          subject: "Final round with the hiring manager", round_label: "final", scheduled_at: s.now - 18.days,
          body: "We'd love for you to meet our hiring manager for a final conversation."),
  s.email(12, "globex-5", 10, "offer", company: "Globex", role: "Data Engineer", from: "Sam at Globex <sam@globex.com>",
          subject: "Offer letter - Data Engineer", body: "We're delighted to extend you an offer. Please find the offer letter attached."),

  # Initech: applied long ago, never heard back (ghosted).
  s.email(13, "initech-1", 90, "applied", company: "Initech Technologies Pvt Ltd", role: "SDE 2", from: "Naukri <info@naukri.com>",
          subject: "Your application was sent to Initech Technologies", body: "Your application for SDE 2 was successfully sent to the recruiter."),

  # Northwind: quick rejection via Workday.
  s.email(14, "northwind-1", 35, "applied", company: "Northwind", role: "Frontend Engineer", from: "Northwind <northwind@myworkday.com>",
          subject: "We have received your application", body: "Thank you for your interest in Northwind. We have received your application."),
  s.email(15, "northwind-2", 33, "rejection", company: "Northwind", role: "Frontend Engineer", from: "Northwind <northwind@myworkday.com>",
          subject: "Update on your application", body: "After careful review we have decided to pursue other candidates for this position."),

  # Contoso: upcoming interview.
  s.email(16, "contoso-1", 20, "applied", company: "Contoso", role: "Platform Engineer", from: "Contoso <no-reply@ashbyhq.com>",
          subject: "Thanks for applying to Contoso", body: "Thanks for applying for Platform Engineer at Contoso!"),
  s.email(17, "contoso-2", 4, "interview_scheduled", company: "Contoso", role: "Platform Engineer", from: "Contoso <no-reply@ashbyhq.com>",
          subject: "Interview scheduled: Platform Engineer", round_label: "technical round", scheduled_at: s.now + 3.days,
          body: "Your interview has been scheduled. A calendar invite with the video link is attached."),

  # Fabrikam: recruiter reached out first (company domain, no ATS), interview upcoming.
  s.email(18, "fabrikam-1", 15, "recruiter_outreach", company: nil, role: "ML Engineer", from: "Dana <dana@careers.fabrikam.com>",
          subject: "Opportunity at Fabrikam", body: "Hi! I came across your profile and think you'd be a great fit for our ML Engineer role."),
  s.email(19, "fabrikam-1", 7, "interview_scheduled", company: nil, role: "ML Engineer", from: "Dana <dana@careers.fabrikam.com>",
          subject: "RE: Opportunity at Fabrikam", round_label: "intro call", scheduled_at: s.now + 2.days,
          body: "Great, I've booked a 30-minute intro call with the hiring manager."),

  # Tailspin: LinkedIn Easy Apply, rejected.
  s.email(20, "tailspin-1", 70, "applied", company: "Tailspin Toys", role: "Backend Engineer", from: "LinkedIn <jobs-noreply@linkedin.com>",
          subject: "Your application was sent to Tailspin Toys", body: "Your application was sent to Tailspin Toys. Backend Engineer."),
  s.email(21, "tailspin-2", 68, "rejection", company: "Tailspin Toys", role: "Backend Engineer", from: "Tailspin Toys <careers@tailspin.io>",
          subject: "Your application to Tailspin Toys", body: "We regret to inform you that we will not be moving forward."),

  # Pinecrest Labs: AI screen done, stalled.
  s.email(22, "pinecrest-1", 25, "applied", company: "Pinecrest Labs", role: "Software Engineer", from: "Pinecrest Labs <noreply@smartrecruiters.com>",
          subject: "Application received", body: "Thank you for applying to Pinecrest Labs."),
  s.email(23, "pinecrest-2", 22, "ai_screen", company: "Pinecrest Labs", role: "Software Engineer", from: "Pinecrest Labs <noreply@smartrecruiters.com>",
          subject: "Complete your AI interview", round_label: "AI screening", body: "Please complete an asynchronous AI video interview."),

  # Recent applications with no reply yet.
  s.email(24, "bluefin-1", 10, "applied", company: "Bluefin Robotics", role: "Embedded Engineer", from: "Bluefin Robotics <#{gh}>",
          subject: "Thank you for applying to Bluefin Robotics", body: "We received your application for Embedded Engineer."),
  s.email(25, "quill-1", 5, "applied", company: "Quillstone Solutions", role: "Full Stack Developer", from: "Quillstone <no-reply@hire.lever.co>",
          subject: "Quillstone - application received", body: "Thanks for your interest in Quillstone."),

  # Orbitly: offer then withdrew.
  s.email(26, "orbitly-1", 50, "applied", company: "Orbitly", role: "Site Reliability Engineer", from: "Orbitly <no-reply@ashbyhq.com>",
          subject: "Thanks for applying to Orbitly", body: "Thanks for applying for Site Reliability Engineer."),
  s.email(27, "orbitly-2", 20, "offer", company: "Orbitly", role: "Site Reliability Engineer", from: "Kim <kim@orbitly.dev>",
          subject: "Offer from Orbitly", body: "We're excited to offer you the SRE position."),
  s.email(28, "orbitly-2", 18, "withdrawn", company: "Orbitly", role: "Site Reliability Engineer", from: "Kim <kim@orbitly.dev>",
          subject: "RE: Offer from Orbitly", body: "Confirming you've withdrawn from the process. Best of luck!"),

  # Lakeshore: two roles at the same company stay separate.
  s.email(29, "lake-1", 30, "applied", company: "Lakeshore Analytics", role: "Data Analyst", from: "Lakeshore <#{gh}>",
          subject: "Thank you for applying to Lakeshore Analytics", body: "Application for Data Analyst received."),
  s.email(30, "lake-2", 25, "rejection", company: "Lakeshore Analytics", role: "Data Analyst", from: "Lakeshore <#{gh}>",
          subject: "Your Lakeshore Analytics application", body: "We won't be moving forward with your Data Analyst application."),
  s.email(31, "lake-3", 28, "applied", company: "Lakeshore Analytics", role: "Analytics Engineer", from: "Lakeshore <#{gh}>",
          subject: "Thank you for applying to Lakeshore Analytics", body: "Application for Analytics Engineer received."),
  s.email(32, "lake-4", 20, "interview_scheduled", company: "Lakeshore Analytics", role: "Analytics Engineer", from: "Lakeshore <#{gh}>",
          subject: "Interview invitation", round_label: "technical round", scheduled_at: s.now - 17.days,
          body: "We'd like to schedule a technical interview for Analytics Engineer."),

  # Noise: job alerts never create applications.
  s.email(33, "alert-1", 3, "job_alert", company: nil, from: "LinkedIn Job Alerts <jobalerts-noreply@linkedin.com>",
          subject: "30 new jobs for 'backend engineer'", body: "Backend Engineer at Acme... Senior SWE at Globex..."),
  s.email(34, "alert-2", 9, "job_alert", company: nil, from: "Naukri <jobs@naukri.com>",
          subject: "Jobs matching your profile", body: "12 new jobs match your profile this week."),

  # Low confidence: waits in the review queue, excluded from counts.
  s.email(35, "wingtip-1", 6, "rejection", company: "Wingtip", role: nil, from: "Wingtip Talent <talent@wingtip.com>",
          subject: "Thank you for your interest", confidence: 0.55, needs_review: true,
          classifier_reason: "Could be a rejection or a generic acknowledgement",
          body: "Thank you for your interest in Wingtip. We will keep your profile on file for future openings.")
]

emails.each { |email| Applications::IngestEmail.call(email) }

# A manual application with no email behind it.
manual = Application.find_or_create_by!(company_key: "harborview", manual: true) do |app|
  app.company_name = "Harborview"
  app.role = "Backend Engineer"
  app.role_key = "backend engineer"
  app.source = "manual"
  app.notes = "Applied through a referral."
end
manual.events.find_or_create_by!(kind: "applied") { |event| event.occurred_at = s.now - 12.days }
Applications::InferStatus.call(manual)

puts "Synthetic seed data loaded."
