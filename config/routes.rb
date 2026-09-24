Rails.application.routes.draw do
  root "dashboard#show"

  resources :applications, only: %i[index show new create] do
    resources :events, only: %i[create destroy], controller: "application_events"
  end
  resources :emails, only: %i[show]
  resources :reviews, only: %i[index update]
  resource :sync, only: %i[show create]
  resource :gmail_connection, only: %i[create]

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
