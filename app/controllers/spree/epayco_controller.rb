module Spree
  class EpaycoController < BaseController
    skip_before_action :verify_authenticity_token, only: [:update_payment_status]

    def redirect_to_gateway
      payment = Spree::Payment.find_by_number params[:payment_number]
      order = payment.order
      byebug
      gateway = Spree::PaymentMethod.find_by_type 'Spree::Gateway::MollieGateway'
      @api_key = gateway.get_preference(:api_key)
      @price = order.total
      @email = order.email
      @name = order.billing_address.full_name
      @billing_address = parse_address(order.billing_address)
      @base_url_webhook = gateway.get_preference(:hostname)
      @tx_id = params[:payment_number]
      # TODO taxes and description
    end


    # When the user is redirected from Mollie back to the shop, we can check the
    # mollie transaction status and set the Spree order state accordingly.
    def validate_payment
      order_number, payment_number = split_payment_identifier params[:order_number]
      payment = Spree::Payment.find_by_number payment_number
      order = Spree::Order.find_by_number order_number
      mollie = Spree::PaymentMethod.find_by_type 'Spree::Gateway::MollieGateway'
      mollie.update_payment_status payment

      EpaycoLogger.debug("Redirect URL visited for order #{params[:order_number]}")

      order = order.reload

      # Order is paid for or authorized (e.g. Klarna Pay Later)
      redirect_to order.paid? || payment.pending? ? order_path(order) : checkout_state_path(:payment)
    end

    # Mollie might send us information about a transaction through the webhook.
    # We should update the payment state accordingly.
    def update_payment_status
      EpaycoLogger.debug("Webhook called for Mollie order #{params[:id]}")

      payment = Spree::MolliePaymentSource.find_by_payment_id(params[:id]).payments.first
      mollie = Spree::PaymentMethod.find_by_type 'Spree::Gateway::MollieGateway'
      mollie.update_payment_status payment

      head :ok
    end

    private

    # Payment identifier is a combination of order_number and payment_id.
    def split_payment_identifier(payment_identifier)
      payment_identifier.split '-'
    end

    def parse_address(address)
      [
       address.address1,
       address.address2,
       "#{address.city}, #{address.state_text} #{address.zipcode}",
       address.country.to_s
      ].reject(&:blank?).map { |attribute| ERB::Util.html_escape(attribute) }.join('. ')
    end

  end
end
