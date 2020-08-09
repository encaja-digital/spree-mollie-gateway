Spree::Core::Engine.routes.draw do
  resource :epayco, only: [], controller: :epayco do
    post 'update_payment_status/:order_number', action: :update_payment_status, as: 'epayco_update_payment_status'
    get 'validate_payment/:order_number', action: :validate_payment, as: 'epayco_validate_payment'
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
