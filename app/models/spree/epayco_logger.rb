module Spree
  class EpaycoLogger
    def self.debug(message = nil)
      return unless message.present?

      @logger ||= Logger.new(File.join(Rails.root, 'log', 'epayco.log'))
      @logger.debug(message)
    end

    class << self
      attr_writer :logger
    end
  end
end
