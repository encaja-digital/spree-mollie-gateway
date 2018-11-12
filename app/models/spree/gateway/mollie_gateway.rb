module Spree
  class Gateway::MollieGateway < PaymentMethod
    include Spree::Mollie::MoneyFormatter

    preference :api_key, :string
    preference :hostname, :string

    has_many :spree_mollie_payment_sources, class_name: 'Spree::MolliePaymentSource'

    # Only enable one-click payments if spree_auth_devise is installed
    def self.allow_one_click_payments?
      Gem.loaded_specs.key?('spree_auth_devise')
    end

    def payment_source_class
      Spree::MolliePaymentSource
    end

    def actions
      %w[credit]
    end

    def provider_class
      ::Mollie::Client
    end

    # Always create a source which references to the selected Mollie payment method.
    def source_required?
      true
    end

    def available_for_order?(_order)
      true
    end

    def auto_capture?
      true
    end

    def gateways(options = {})
      payment_method = Spree::PaymentMethod.find_by_type self.class
      if options[:order].present? && options[:order].is_a?(Spree::Order)
        payment_method.available_methods_for_order(options[:order])
      elsif options[:amount].present?
        payment_method.available_methods(options)
      else
        raise 'Unprocessable input'
      end.map(&:attributes)
    end

    def process(money, source, gateway_options)
      MollieLogger.debug("About to create payment for order #{gateway_options[:order_id]}")

      begin
        order_params = prepare_order_params(money, source, gateway_options)
        mollie_order = ::Mollie::Order.create(order_params)
        MollieLogger.debug("Mollie order #{mollie_order.id} created for Spree order #{gateway_options[:order_id]}")

        source.status = mollie_order.status
        source.payment_id = mollie_order.id
        source.payment_url = mollie_order.checkout_url
        source.save!
        ActiveMerchant::Billing::Response.new(true, 'Order created')
      rescue ::Mollie::Exception => e
        MollieLogger.debug("Could not create payment for order #{gateway_options[:order_id]}: #{e.message}")
        ActiveMerchant::Billing::Response.new(false, "Order could not be created: #{e.message}")
      end
    end

    # Create a Mollie customer which can be passed with a payment.
    # Required for one-click Mollie payments.
    def create_customer(user)
      customer = Mollie::Customer.create(
        email: user.email,
        api_key: get_preference(:api_key)
      )
      MollieLogger.debug("Created a Mollie Customer for Spree user with ID #{customer.id}")
      customer
    end

    # Create a new Mollie refund
    def credit(_credit_cents, payment_id, options)
      order = options[:originator].try(:payment).try(:order)
      order_number = order.try(:number)
      order_currency = order.try(:currency)
      MollieLogger.debug("Starting refund for order #{order_number}")

      begin
        ::Mollie::Payment::Refund.create(
          payment_id: payment_id,
          amount: {
            value: format_money(order.display_total.money),
            currency: order_currency
          },
          description: "Refund Spree Order ID: #{order_number}",
          api_key: get_preference(:api_key)
        )
        MollieLogger.debug("Successfully refunded #{order.display_total} for order #{order_number}")
        ActiveMerchant::Billing::Response.new(true, 'Refund successful')
      rescue ::Mollie::Exception => e
        MollieLogger.debug("Refund failed for order #{order_number}: #{e.message}")
        ActiveMerchant::Billing::Response.new(false, 'Refund unsuccessful')
      end
    end

    def cancel(transaction_id)
      MollieLogger.debug("Starting cancelation for #{transaction_id}")

      begin
        mollie_payment = ::Mollie::Payment.get(
          transaction_id,
          api_key: get_preference(:api_key)
        )
        if mollie_payment.cancelable?
          mollie_payment.delete(transaction_id)
          ActiveMerchant::Billing::Response.new(true, 'Mollie payment has been cancelled')
        else
          MollieLogger.debug("Mollie payment #{transaction_id} is not cancelable. Skipping any further updates.")
          ActiveMerchant::Billing::Response.new(true, 'Mollie payment has not been cancelled because it is not cancelable')
        end
      rescue Mollie::Exception => e
        MollieLogger.debug("Payment #{transaction_id} could not be canceled: #{e.message}")
        ActiveMerchant::Billing::Response.new(false, 'Payment cancellation unsuccessful')
      end
    end

    def available_methods(params = nil)
      method_params = {
        api_key: get_preference(:api_key),
        include: 'issuers'
      }

      method_params.merge! params if params.present?

      ::Mollie::Method.all(method_params)
    end

    def available_methods_for_order(order)
      params = {
        amount: {
          currency: order.currency,
          value: format_money(order.display_total.money)
        }
      }
      available_methods(params)
    end

    def update_payment_status(payment)
      mollie_transaction_id = payment.source.payment_id
      mollie_payment = ::Mollie::Payment.get(
        mollie_transaction_id,
        api_key: get_preference(:api_key)
      )

      MollieLogger.debug("Checking Mollie payment status. Mollie payment has status #{mollie_payment.status}")
      update_by_mollie_status!(mollie_payment, payment)
    end

    def update_by_mollie_status!(mollie_payment, payment)
      case mollie_payment.status
      when 'paid'
        # If Mollie payment is already paid and refunded amount is more than 0, don't update payment
        if mollie_payment.paid? && mollie_payment.amount_refunded.value > 0
          MollieLogger.debug('Payment is refunded. Not updating the payment status within Spree.')
          return
        end

        if payment.completed?
          MollieLogger.debug('Payment is already completed. Not updating the payment status within Spree.')
          return
        end

        # If order is already paid for, don't mark it as complete again.
        payment.complete!
        payment.order.finalize!
        payment.order.update_attributes(state: 'complete', completed_at: Time.now)
        MollieLogger.debug('Payment is paid and will transition to completed. Order will be finalized.')
      when 'canceled', 'expired', 'failed'
        payment.failure! unless payment.failed?
        payment.order.update_attributes(state: 'payment', completed_at: nil)
      else
        MollieLogger.debug('Unhandled Mollie payment state received. Therefore we did not update the payment state.')
        payment.order.update_attributes(state: 'payment', completed_at: nil)
      end

      payment.source.update(status: payment.state)
    end

    private

    def prepare_order_params(money, source, gateway_options)
      gateway_preferences = {
        hostname: get_preference(:hostname),
        api_key: get_preference(:api_key)
      }
      Spree::Mollie::OrderSerializer.serialize(money, source, gateway_options, gateway_preferences)
    end
  end
end
