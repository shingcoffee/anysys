# frozen_string_literal: true

module Authentication
  # Enumeration-safe enqueue for the public customer sign-up link.
  # Unknown addresses get a confirmation mail; taken addresses are a no-op.
  # Callers always show the same check-email page either way.
  #
  # Mail is enqueued, never delivered inline — a synchronous SMTP round trip
  # would make a registered address slower than an unknown one.
  class IssueCustomerSignup
    def self.call(...)
      new(...).call
    end

    def initialize(email:)
      @email = email
    end

    def call
      email = CustomerSignupToken.normalize(@email)
      return if email.blank?
      return if User.find_by_normalized_email(email)

      token = CustomerSignupToken.generate(email)
      CustomerSignupMailer.instructions(email, token).deliver_later
      nil
    end
  end
end
