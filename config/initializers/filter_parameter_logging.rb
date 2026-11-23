# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate,
  :otp, :otp_code, :totp, :totp_code, :mfa, :mfa_code,
  :sign_in_code,
  :ssn, :cvv, :cvc, :cvv2,
  :credit_card, :card_number, :pan, :iban, :bank_account,
  :authorization, :access_token, :refresh_token, :bearer,
  :code_verifier, :code_challenge,
  /\Acode\z/i, # Member TOTP and OAuth authorization codes, including nested payloads.
  /\A_?run\z/ # Journey run tokens (`?run=` links and the hidden `_run` form field).
]

# SMS handoffs use top-level `vars`/`to`; Twilio sends `From`/`To`/`Body`.
# Filter these exact names globally so query-string logging is protected too
# (it has no controller/route context). Avoid broad :body/:phone or substring
# matches, which would hide unrelated configuration and diagnostic fields.
# Rails filters raw query keys without decoding nested bracket notation.
Rails.application.config.filter_parameters += [/\A(?:vars(?:\[|%5[Bb])|(?:vars|to|From|To|Body)\z)/]
