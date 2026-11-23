# frozen_string_literal: true

require "rqrcode"

module Payments
  # Renders a scannable QR code for desktop-initiated payments
  # (WeChat "Native" mode or Alipay page/qr mode). Paired with the
  # `payments--qr-poll` Stimulus controller which polls status and
  # redirects on completion.
  class QrCodeComponent < ApplicationComponent
    def initialize(payment:)
      @payment  = payment
      @code_url = payment.prepay_payload["code_url"] || payment.prepay_payload["qr_code"]
    end

    attr_reader :payment, :code_url

    def qr_provider_label
      Payments::Gateways.for(payment.provider).display_name
    rescue ArgumentError
      payment.provider.to_s
    end

    # The PSP-issued code_url carries a short-lived authorization the
    # shopper's browser must trust — it must never be sent to a third-party
    # image service. We render the QR as inline SVG server-side instead.
    def qr_svg
      return "" if code_url.to_s.empty?
      RQRCode::QRCode.new(code_url.to_s, level: :m).as_svg(
        offset: 0,
        color: "000",
        shape_rendering: "crispEdges",
        module_size: 5,
        standalone: true,
        use_path: true
      ).html_safe
    end

    # JSON object of localized status tokens for payments--qr-poll.
    # ERB HTML-escapes the quotes so the data attribute stays well-formed.
    def status_labels_json
      %i[pending succeeded failed closed].index_with do |status|
        I18n.t("comp_payments.result.statuses.#{status}")
      end.to_json
    end
  end
end
