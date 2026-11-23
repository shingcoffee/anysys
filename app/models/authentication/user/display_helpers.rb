# frozen_string_literal: true

module Authentication
  class User < ApplicationRecord
    # DisplayHelpers
    #
    # Pure presentation helpers for Authentication::User. No auth, role, or
    # Devise state is involved — these methods operate only on +first_name+,
    # +last_name+, and +email+.
    module DisplayHelpers
      extend ActiveSupport::Concern

      def full_name
        "#{first_name} #{last_name}".strip
      end

      def display_name
        full_name.presence || email
      end
    end
  end
end
