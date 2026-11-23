# frozen_string_literal: true

module Authentication
  # Response hardening for pages that render, or are addressed by, a secret.
  #
  # Two distinct cases need it:
  #   * the MFA enrolment screens, which print the TOTP secret in the body for
  #     manual entry, and
  #   * the emailed-link endpoints, whose secret is in the query string and so
  #     ends up in the address bar, browser history, and the Referer header of
  #     anything the rendered page subsequently requests.
  #
  # `no-store` keeps the body out of browser and intermediary caches — which
  # matters most on shared devices, where the back/forward cache would
  # otherwise hand the previous user's secret to the next one — and
  # `no-referrer` stops the URL itself leaking onward.
  module NoStore
    extend ActiveSupport::Concern

    private

    def no_store!
      response.headers["Cache-Control"]   = "no-store, no-cache, must-revalidate, private"
      response.headers["Pragma"]          = "no-cache"
      response.headers["Referrer-Policy"] = "no-referrer"
    end
  end
end
