# The review queue: low-confidence or unparseable classifications, one at a time.
class ReviewsController < ApplicationController
  def index
    @remaining = Email.review_queue.count
    @email = Email.review_queue.order(:sent_at, :id).first
  end

  def update
    email = Email.find(params[:id])

    if params[:discard]
      email.update!(review_state: "discarded")
      notice = "Discarded as noise."
    else
      category = params[:category].presence_in(Tracker::EMAIL_CATEGORIES)
      return redirect_to(reviews_path, alert: "Pick a category.") unless category

      email.update!(category: category, extracted_company: params[:company].presence,
                    extracted_role: params[:role].presence, review_state: "confirmed",
                    classified_at: email.classified_at || Time.current)
      notice = "Confirmed as #{category.humanize.downcase}."
    end

    application = Applications::IngestEmail.call(email)
    if email.eligible? && application.nil?
      notice += " It couldn't be matched to a company — add the company name to group it."
    end
    redirect_to reviews_path, notice: notice
  end
end
