module Spree
  module CheckoutWithMollie
    # If we're currently in the checkout
    def update
      EpaycoLogger.debug("payment_params_valid? #{payment_params_valid?} && paying_with_mollie? #{payment_params_valid? && paying_with_mollie?}")
      if payment_params_valid? && paying_with_mollie?
        if @order.update_from_params(params, permitted_checkout_attributes, request.headers.env)
          payment = @order.payments.last
          payment.process!
          mollie_payment_url = payment.payment_source.payment_url

          EpaycoLogger.debug("For order #{@order.number} redirect user to payment URL: #{mollie_payment_url}")

          # TODO send payment and order
          redirect_to epayco_redirect_epayco_path(payment_number: payment.number)
        else
          render :edit
        end
      else
        super
      end
    end
  end

  module CheckoutControllerDecorator
    def payment_method_id_param
      params[:order][:payments_attributes].first[:payment_method_id]
    end

    def paying_with_mollie?
      payment_method = PaymentMethod.find(payment_method_id_param)
      payment_method.is_a? Gateway::MollieGateway
    end

    def payment_params_valid?
      (params[:state] === 'payment') && params[:order][:payments_attributes]
    end
  end

  CheckoutController.prepend(CheckoutWithMollie)
  CheckoutController.prepend(CheckoutControllerDecorator)

end
