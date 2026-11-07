Rails.application.routes.draw do
  # www.stepsfrom.com → stepsfrom.com, keeping the path and query.
  app_host = ENV.fetch("APP_HOST", "stepsfrom.com")
  constraints(host: "www.#{app_host}") do
    get "(*path)", to: redirect(status: 301) { |_params, request| "#{request.protocol}#{app_host}#{request.fullpath}" }
  end

  root "home#index"

  get "search", to: "search#show", as: :search
  resources :destinations, only: :show
  resources :properties, only: :show

  # Outbound click to a booking site; logged, then redirected.
  get "go/:listing_id", to: "outbound#show", as: :outbound

  get "how-we-verify", to: "pages#how_we_verify", as: :how_we_verify
  get "affiliate-disclosure", to: "pages#affiliate_disclosure", as: :affiliate_disclosure
  get "privacy", to: "pages#privacy", as: :privacy
  get "sitemap.xml", to: "sitemaps#show", as: :sitemap, defaults: { format: :xml }
  get "robots.txt", to: "pages#robots", as: :robots, defaults: { format: :text }

  namespace :admin do
    root "properties#index"
    get "login", to: "sessions#new", as: :login
    post "login", to: "sessions#create"
    delete "logout", to: "sessions#destroy", as: :logout
    resources :destinations, except: :show do
      post :import, on: :member
    end
    resources :imports, only: :index
    resources :properties do
      member do
        post :hide
        post :unhide
        post :reclassify
      end
      resources :listings, except: %i[index show]
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
