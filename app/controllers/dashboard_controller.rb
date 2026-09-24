class DashboardController < ApplicationController
  def show
    @analytics = Tracker::Analytics.new
  end
end
