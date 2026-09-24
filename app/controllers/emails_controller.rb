class EmailsController < ApplicationController
  def show
    @email = Email.find(params[:id])
  end
end
