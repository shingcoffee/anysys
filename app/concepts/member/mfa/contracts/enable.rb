# frozen_string_literal: true

module Member
  module Mfa
    module Contracts
      class Enable < Reform::Form
        property :code

        validates :code, presence: true, format: { with: /\A\d{6}\z/, message: :invalid }
      end
    end
  end
end
