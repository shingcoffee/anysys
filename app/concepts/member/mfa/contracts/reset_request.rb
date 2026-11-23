# frozen_string_literal: true

module Member
  module Mfa
    module Contracts
      class ResetRequest < Reform::Form
        property :email

        validates :email,
                  presence: true,
                  format:   { with: URI::MailTo::EMAIL_REGEXP }
      end
    end
  end
end
