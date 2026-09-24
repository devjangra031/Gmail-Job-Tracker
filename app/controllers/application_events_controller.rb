# Updates you add by hand to an application (no email behind them).
class ApplicationEventsController < ApplicationController
  before_action :set_application

  def create
    form = params.expect(event: %i[kind occurred_on note round_label scheduled_at])
    event = Applications::AddManualEvent.call(@application, **form.to_h.symbolize_keys)

    if event.persisted?
      redirect_to @application, notice: "Added: #{helpers.kind_label(event.kind)} on #{event.occurred_at.strftime('%d %b')}."
    else
      redirect_to @application, alert: event.errors.full_messages.to_sentence
    end
  end

  # Only hand-added updates can be removed; email-backed events come from the email.
  def destroy
    event = @application.events.where(email_id: nil).find(params[:id])
    event.destroy!
    Applications::InferStatus.call(@application)
    redirect_to @application, notice: "Removed that update."
  end

  private

  def set_application
    @application = Application.find(params[:application_id])
  end
end
