Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "parlamentares#index"

  resources :parlamentares, only: %i[index show] do
    collection do
      post :sincronizar_todos
    end
    member do
      get :propostas
      post :sincronizar
    end
  end

  resources :propostas, only: %i[index show] do
    collection do
      post :sincronizar_recentes
    end
    member do
      post :sincronizar
    end
  end
end
