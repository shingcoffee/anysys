# frozen_string_literal: true

module Payments
  # Renders the H5 bridge page that hands off to the provider's in-app
  # payment flow (mobile web / WAP). Paired with the
  # `payments--h5-redirect` Stimulus controller, which performs the
  # actual `window.location` jump shortly after mount.
  class H5RedirectComponent < ApplicationComponent
    def initialize(payment:)
      @payment = payment
      @url     = payment.prepay_payload["h5_url"]
    end

    attr_reader :payment, :url
  end
end
