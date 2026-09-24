class ApplicationsController < ApplicationController
  def index
    @filter = Applications::Filter.new(params)
    @applications = @filter.relation.includes(:events)
    @sources = Application.distinct.order(:source).pluck(:source)
  end

  def show
    @application = Application.find(params[:id])
    @events = @application.events.includes(:email)
  end

  def new
    @application = Application.new(source: "manual")
  end

  def create
    form = params.expect(application: %i[company_name role source applied_on notes])
    @application = Applications::CreateManual.call(**form.to_h.symbolize_keys)

    if @application.persisted?
      redirect_to @application, notice: "Added #{@application.company_name}."
    else
      render :new, status: :unprocessable_content
    end
  end
end
