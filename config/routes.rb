Spree::Core::Engine.routes.draw do
  resource :epayco, only: [], controller: :epayco do
    post 'payment_confirmation/:payment_number', action: :payment_confirmation, as: 'epayco_payment_confirmation'
    get 'payment_response/:payment_number', action: :payment_result
    post 'payment_response/:payment_number', action: :payment_result, as: 'epayco_payment_response'
    get 'redirect/:payment_number', action: :redirect_to_gateway, as: 'epayco_redirect'
  end

  namespace :api do
    namespace :v1 do
      resources :mollie, only: [] do
        collection do
          get :methods
        end
      end
    end
  end
end
