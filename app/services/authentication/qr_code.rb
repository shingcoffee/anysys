# frozen_string_literal: true

module Authentication
  # Renders a TOTP provisioning URI as an inline SVG for the enrolment screens.
  #
  # Thin wrapper over rqrcode so the admin and member enrolment surfaces share
  # one set of rendering options instead of two copies that can drift apart.
  class QrCode
    OPTIONS = {
      color:           "000",
      shape_rendering: "crispEdges",
      module_size:     4,
      standalone:      true,
      use_path:        true
    }.freeze

    # @param uri [String, nil] an otpauth:// provisioning URI
    # @return [String, nil] SVG markup, or nil when there is no secret yet
    def self.svg(uri)
      return nil if uri.blank?

      RQRCode::QRCode.new(uri).as_svg(**OPTIONS)
    end
  end
end
