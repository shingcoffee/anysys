# frozen_string_literal: true

# Active Record encryption keys.
#
# Production / staging credentials live in config/credentials.yml.enc; this
# initializer fills in deterministic non-secret keys for development and test
# so the suite can exercise `encrypts :col` without a master.key checked in.
#
# Real keys for non-dev environments must be set via:
#   bin/rails db:encryption:init
# and stored in encrypted credentials.

if Rails.env.test? || Rails.env.development?
  Rails.application.config.active_record.encryption.tap do |enc|
    enc.primary_key                   ||= "test-only-primary-key-32-chars-_____"
    enc.deterministic_key              ||= "test-only-deterministic-key-32____"
    enc.key_derivation_salt            ||= "test-only-key-derivation-salt-32____"
  end
end

# Transitional setting (ALL environments): `encrypts :otp_secret` was added to an
# existing column that may already hold plaintext TOTP secrets. Without this,
# production would raise ActiveRecord::Encryption::Errors::Decryption reading a
# legacy plaintext row — locking that user (potentially the platform owner) out
# of login/MFA. New writes are always encrypted; this only permits READING
# not-yet-migrated plaintext. It can be turned off once all rows are re-encrypted.
Rails.application.config.active_record.encryption.support_unencrypted_data = true
