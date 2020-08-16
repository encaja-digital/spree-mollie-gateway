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
      @tax_amount = order.additional_tax_total
      @tax_base = order.item_total
      @items = order.item_count
      @store_name = order.store.name
    end


    # When the user is redirected from Mollie back to the shop, we can check the
    # mollie transaction status and set the Spree order state accordingly.
    def validate_payment
      byebug
      payment = Spree::Payment.find_by_number params[:payment_number]
      order = payment.order
      mollie = Spree::PaymentMethod.find_by_type 'Spree::Gateway::MollieGateway'

      url = "https://secure.epayco.co/validation/v1/reference/#{params[:ref_payco]}"
      response = HTTParty.get(url)
      parsed = JSON.parse(response.body)

      if parsed['success']
        @data = parsed['data']
        order = order.reload
      else
        @error = 'No se pudo consultar la información'
      end




      #mollie.update_payment_status payment
      # TODO check status and update based on payloads

      EpaycoLogger.debug("Redirect URL visited for order #{params[:order_number]}")

      order = order.reload

      # Order is paid for or authorized (e.g. Klarna Pay Later)
      redirect_to order.paid? || payment.pending? ? order_path(order) : checkout_state_path(:payment)
    end

    # Mollie might send us information about a transaction through the webhook.
    # We should update the payment state accordingly.
    def update_payment_status
      byebug
      EpaycoLogger.debug("Webhook called for Mollie order #{params[:id]}")

      payment = Spree::MolliePaymentSource.find_by_payment_id(params[:id]).payments.first
      mollie = Spree::PaymentMethod.find_by_type 'Spree::Gateway::MollieGateway'
      mollie.update_payment_status payment

      head :ok
    end

    private

    def result
      url = "https://secure.epayco.co/validation/v1/reference/#{params[:ref_payco]}"
      response = HTTParty.get(url)

      parsed = JSON.parse(response.body)
      if parsed['success']
        @data = parsed['data']
        @charge = TransactionLog.where(uid: @data['x_id_invoice']).take
      else
        @error = 'No se pudo consultar la información'
      end
    end

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
