# frozen_string_literal: true

require "digest"

module Captcha
  # Anonymous sessions may not have an id. Keep a random secret in the encrypted
  # session and only its digest in the cache. reset_session invalidates both
  # snapshots and one-use outage passages.
  module SessionBinding
    KEY = "captcha_binding"

    module_function

    def digest(session, create: false)
      secret = session[KEY]
      secret = session[KEY] = SecureRandom.urlsafe_base64(32) if create && secret.blank?
      Digest::SHA256.hexdigest(secret) if secret.is_a?(String) && secret.present?
    end

    def matches?(session, expected)
      actual = digest(session)
      actual.present? && expected.is_a?(String) &&
        ActiveSupport::SecurityUtils.secure_compare(actual, expected)
    end
  end
end
