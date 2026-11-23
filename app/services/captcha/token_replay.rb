# frozen_string_literal: true

module Captcha
  # Short-lived single-use ledger for captcha tokens. A successful verify
  # writes the digest here so the same token cannot pass twice. Failures
  # are not recorded. Captcha tokens are short-lived (vendor TTLs are
  # ~2–5 min); 10 minutes covers any still-valid token.
  class TokenReplay
    WINDOW = 10.minutes

    def self.consumed?(digest)
      return false if digest.blank?

      Rails.cache.exist?(cache_key(digest))
    end

    # Returns false when this digest was already consumed (replay).
    def self.consume!(digest)
      return true if digest.blank?

      Rails.cache.write(cache_key(digest), true, expires_in: WINDOW, unless_exist: true)
    end

    def self.cache_key(digest)
      "captcha:token:#{digest}"
    end
  end
end
