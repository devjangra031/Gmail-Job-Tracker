module Tracker
  class Classifier
    # Provider-agnostic prompt. The examples mirror the wording and layout of real
    # inbox mail (LinkedIn, Naukri, Workday, recruiter invites, calendar reminders)
    # with invented names.
    module Prompt
      BODY_LIMIT = 1500
      SHORT_BODY = 200

      module_function

      def system(time_zone: Time.zone)
        <<~PROMPT
          You classify emails from a job seeker's inbox for a job-application tracker.
          Reply with one JSON object and nothing else, using exactly these keys:
          {"category": string, "company": string|null, "role": string|null, "round_label": string|null,
           "round_hint": integer|null, "is_reschedule": boolean, "scheduled_at": string|null,
           "confidence": number, "reason": string}

          category, one of:
          - applied: confirms the candidate applied ("your application was sent to X", "Application Successful",
            "we have received your application", "thank you for applying ... in the review stage"), or an
            outgoing email in which the candidate applies or sends their CV.
          - shortlisted: the company shortlisted or selected the application for next steps, without yet
            scheduling anything ("your application was shortlisted by X from Company", "you have been
            shortlisted", "your profile has been moved forward").
          - ai_screen: invitation to an automated / AI / asynchronous video screening.
          - assessment: online test, coding challenge or take-home assignment.
          - recruiter_outreach: a recruiter or company approaching the candidate about a specific role they
            did not apply to.
          - interview_scheduled: an interview with a person is invited, scheduled, confirmed or rescheduled,
            including calendar reminders for it.
          - interview_completed: thanks for attending an interview, no decision yet.
          - rejection: any decision not to proceed: not selected, "moving forward with another candidate",
            "resume did not meet the requirements", position closed, "no longer recruiting for this role".
            Polite lines like "we will keep your resume on file" do not change this.
          - offer: a job offer is extended.
          - withdrawn: the candidate withdrew from the process.
          - other: about one of the candidate's applications but none of the above
            (e.g. "your application was viewed by X", a request for documents).
          - job_alert: anything not about an application the candidate made: job recommendations,
            "X is hiring", "be an early applicant", "jobs similar to", saved-job reminders, "a recruiter
            viewed your profile", newsletters, marketing.

          Fields:
          - company: the hiring employer as written. Never a job board, ATS or tool (LinkedIn, Naukri,
            hirist, Cutshort, Instahyre, Workday, Greenhouse, Lever, Google Calendar). null when unknown and
            for job_alert.
          - role: the job title as written, else null.
          - round_label: short stage name as the email puts it ("L1 Interview", "technical round",
            "HR round", "AI screening", "online assessment", "final"), else null.
          - round_hint: an integer only when the email numbers the round: "L1" -> 1, "L2" -> 2,
            "Round 2" -> 2, "second round" -> 2. Otherwise null.
          - is_reschedule: true only if the email says an existing interview was moved or rescheduled.
          - scheduled_at: the interview date and time in ISO 8601 with offset, if stated. Resolve the
            year from the email's Date. Without a stated zone use #{time_zone.name} (#{time_zone.formatted_offset}).
            Otherwise null.
          - confidence: 0 to 1, how sure you are of the category.
          - reason: at most 12 words.

          Hints:
          - "LinkedIn email type" is reliable: application_confirmation* -> applied;
            jobs_application_rejected -> rejection; jobs_job_application_viewed -> other;
            *_reminder, facet_suggestions, job alerts -> job_alert. Take company and role from the subject
            when the body is empty.
          - A LinkedIn confirmation body starts "Your application was sent to <Company> <Role> <Company>
            <Location>". Jobs listed after "View similar jobs" are recommendations, not applications.
          - "Direction: outgoing" means the candidate wrote the email.
          - Job platforms (Cutshort, Naukri, Instahyre, hirist, LinkedIn) forward recruiter messages
            ("X from Company sent you a message", "New message from X"). Classify by what the quoted message
            says (an interview invite is interview_scheduled, a no is rejection, a question about the
            application is other) and take the company from the recruiter's company, not the platform.
            If the message text isn't included, use other.
          - "Notification: ... You have an upcoming event" from Google Calendar is a reminder for an
            interview: interview_scheduled, with company, role and round from the event details.

          Examples:

          From: LinkedIn <jobs-noreply@linkedin.com>
          Subject: Alex, your application was sent to Brightwave Labs
          LinkedIn email type: application_confirmation_with_nba
          Body: Your application was sent to Brightwave Labs Senior Backend Engineer (Ruby) Brightwave Labs
          Pune View job: | Applied on March 3, 2026 | Now, take these next steps View similar jobs ...
          -> {"category":"applied","company":"Brightwave Labs","role":"Senior Backend Engineer (Ruby)",
          "round_label":null,"round_hint":null,"is_reschedule":false,"scheduled_at":null,"confidence":0.97,
          "reason":"LinkedIn application confirmation"}

          From: LinkedIn <jobs-noreply@linkedin.com>
          Subject: Your application to Backend Engineer (SDE II) at Tessellate
          LinkedIn email type: jobs_application_rejected
          Body: Your update from Tessellate | This email was intended for Alex Kumar ...
          -> {"category":"rejection","company":"Tessellate","role":"Backend Engineer (SDE II)",
          "round_label":null,"round_hint":null,"is_reschedule":false,"scheduled_at":null,"confidence":0.9,
          "reason":"LinkedIn application rejected notification"}

          From: Neha Rao <neha.rao@kestrelsoft.com>
          Date: 2026-03-09T11:02:00+05:30 (Monday)
          Subject: L1 Interview | ALEX KUMAR | Backend Engineer(ROR)
          Body: Hi Alex, Greetings of the day! Your interview has been confirmed for 11th March, i.e.
          Wednesday, at Kestrel Softech Pvt. Ltd. Time: 10:00 PM Medium: Virtual ... Microsoft Teams meeting
          -> {"category":"interview_scheduled","company":"Kestrel Softech Pvt. Ltd.",
          "role":"Backend Engineer(ROR)","round_label":"L1 Interview","round_hint":1,"is_reschedule":false,
          "scheduled_at":"2026-03-11T22:00:00+05:30","confidence":0.96,"reason":"L1 interview confirmed"}

          From: Orbit Health <orbithealth@myworkday.com>
          Subject: Update on Your Application for the Engineering Manager role at Orbit Health
          Body: Dear Alex, We appreciate the time and effort you invested in applying ... Regrettably, after
          careful consideration, your resume did not meet the requirements necessary to proceed to the next
          stage ... we will keep your application on file.
          -> {"category":"rejection","company":"Orbit Health","role":"Engineering Manager","round_label":null,
          "round_hint":null,"is_reschedule":false,"scheduled_at":null,"confidence":0.95,
          "reason":"Resume did not meet requirements"}

          From: Cutshort <notify@cutshort.io>
          Subject: Neha from Quanta sent you a message
          Body: Hey Alex, Neha from Quanta sent you a message about "Backend Engineer (Rails)": "Hi Alex, thanks
          for your interest. Could you join a 45 min technical discussion on Friday 26th Sept at 4 PM?"
          View conversation
          -> {"category":"interview_scheduled","company":"Quanta","role":"Backend Engineer (Rails)",
          "round_label":"technical discussion","round_hint":null,"is_reschedule":false,
          "scheduled_at":"2026-09-26T16:00:00+05:30","confidence":0.9,"reason":"Recruiter message inviting to interview"}

          From: Naukri Alerts <naukrialerts@naukri.com>
          Subject: Lumen Pay is hiring - be an early applicant!
          Body: Hi Alex, I'm Riya, your career concierge. I've found this freshly posted opportunity ...
          -> {"category":"job_alert","company":null,"role":null,"round_label":null,"round_hint":null,
          "is_reschedule":false,"scheduled_at":null,"confidence":0.98,"reason":"Naukri job recommendation"}

          From: Alex Kumar <alex@example.com>
          Direction: outgoing
          Subject: Application regarding Senior Rails Developer
          Body: Hi Rohan, I came across the Senior Rails Developer opportunity at Quanta and would like to
          express my interest ... I'm sharing my CV for your consideration.
          -> {"category":"applied","company":"Quanta","role":"Senior Rails Developer","round_label":null,
          "round_hint":null,"is_reschedule":false,"scheduled_at":null,"confidence":0.9,
          "reason":"Candidate emailed their CV to apply"}
        PROMPT
      end

      def user_message(input)
        body = Cleaner.text(input.body).truncate(BODY_LIMIT)
        lines = []
        lines << "From: #{input.from}"
        lines << "Direction: outgoing" if input.outgoing
        lines << "Date: #{input.sent_at.in_time_zone.iso8601} (#{input.sent_at.in_time_zone.strftime('%A')})" if input.sent_at
        lines << "Subject: #{Cleaner.text(input.subject)}"
        if (type = input.linkedin_type || Cleaner.linkedin_type(input.body))
          lines << "LinkedIn email type: #{type}"
        end
        lines << "Snippet: #{Cleaner.text(input.snippet)}" if body.length < SHORT_BODY && input.snippet.present?
        lines << "Body: #{body.presence || '(empty)'}"
        lines.join("\n")
      end
    end
  end
end
