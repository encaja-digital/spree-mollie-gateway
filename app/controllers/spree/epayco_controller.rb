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
      @tx_id = params[:payment_number] #or payment.source.payment_id
      @tax_amount = order.additional_tax_total
      @tax_base = order.item_total
      @items = order.item_count
      @store_name = order.store.name
    end


    # When the user is redirected from Mollie back to the shop, we can check the
    # mollie transaction status and set the Spree order state accordingly.
    def payment_result
      byebug
      url = "https://secure.epayco.co/validation/v1/reference/#{params[:ref_payco]}"
      response = HTTParty.get(url)

      parsed = JSON.parse(response.body)
      if parsed['success']
        @data = parsed['data'].with_indifferent_access
        @charge = Spree::Payment.find_by_number @data['x_id_invoice']
      else
        @error = 'No se pudo consultar la información'
      end
    end

    def payment_confirmation
      byebug
      url = "https://secure.epayco.co/validation/v1/reference/#{params[:ref_payco]}"
      response = HTTParty.get(url)

      payment = Spree::Payment.find_by_number params[:payment_number]
      order = payment.order
      mollie = Spree::PaymentMethod.find_by_type 'Spree::Gateway::MollieGateway'

      update_status(payment, response)

      # if signature == response[:x_signature]
      #   update_status(payment, response)
      #   head :no_content
      # else
      #   puts "Signature: #{signature}"
      #   puts "Received signature: #{response[:x_signature]}"
      #   head :unprocessable_entity
      # end

      # Order is paid for or authorized (e.g. Klarna Pay Later)
      redirect_to order.paid_or_authorized? || payment.pending? ? order_path(order) : checkout_state_path(:payment)
    end

    def validate_payment
      byebug
      payment = Spree::Payment.find_by_number params[:payment_number]
      order = payment.order
      mollie = Spree::PaymentMethod.find_by_type 'Spree::Gateway::MollieGateway'

      response = result()
      signature = signature(response, mollie)
      ## TODO: check signature before update_status
      update_status(payment, response)

      # if signature == response[:x_signature]
      #   update_status(payment, response)
      #   head :no_content
      # else
      #   puts "Signature: #{signature}"
      #   puts "Received signature: #{response[:x_signature]}"
      #   head :unprocessable_entity
      # end

      # Order is paid for or authorized (e.g. Klarna Pay Later)
      redirect_to order.paid_or_authorized? || payment.pending? ? order_path(order) : checkout_state_path(:payment)
    end

    def update_status(payment, response)
      byebug
      status = response[:x_cod_response]
      if status == 1
        payment.source.update(status: :paid)
        payment.update(state: :paid)
      elsif status == 2 || status == 4
        payment.source.update(status: :rejected, error_message: response[:x_response_reason_text])
        payment.update(state: :rejected)
      elsif status == 3
        payment.source.update(status: :pending)
        payment.update(state: :pending)
      else
        head :unprocessable_entity
        return
      end
    end

    private

    def result()
      url = "https://secure.epayco.co/validation/v1/reference/#{params[:ref_payco]}"
      response = HTTParty.get(url)

      parsed = JSON.parse(response.body)
      if parsed['success']
        return parsed['data'].with_indifferent_access
      else
        @error = 'No se pudo consultar la información'
      end
    end

    def signature(response, mollie)
      msg = "#{response[:x_cust_id_cliente]}^#{mollie.get_preference(:api_key)}^#{response[:x_ref_payco]}^#{response[:x_transaction_id]}^#{response[:x_amount]}^#{response[:x_currency_code]}"
      Digest::SHA256.hexdigest(msg)
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
