# frozen_string_literal: true

require "mail"

# Signature verification can authenticate several retained mode rows sharing a
# vendor key. Only recorded send identity may disambiguate them. Unknown events
# with one verified identity are safe to persist; ambiguous events get HTTP 409
# so ingress never assigns an arbitrary credential to a durable receipt.
class WebhookCredentialBinding
  class Ambiguous < StandardError; end

  def self.call(credentials:, messages:)
    candidates = credentials.index_by { |credential| credential.id.to_s }
    matched = messages.filter_map do |message|
      credential = candidates[(message.metadata || {})["credential_id"].to_s]
      next unless credential && recorded_match?(message, credential)
      next if block_given? && !yield(message)

      credential
    end.uniq(&:id)
    return matched.first if matched.one?
    return credentials.first if matched.empty? && credentials.one?

    raise Ambiguous, "verified callback has no unique recorded credential identity"
  end

  def self.recorded_match?(message, credential)
    identity = message.metadata || {}
    message.provider == credential.provider && identity["credential_id"].to_s == credential.id.to_s &&
      (identity["credential_mode"].blank? || identity["credential_mode"] == credential.mode)
  end

  def self.email_recipient?(message, email)
    return true if email.blank?

    expected = email.to_s.strip.downcase
    [message.to, message.cc, message.bcc].compact.any? do |value|
      Mail::AddressList.new(value).addresses.any? { |address| address.address.to_s.strip.downcase == expected }
    end
  rescue Mail::Field::ParseError
    false
  end
end
