# frozen_string_literal: true

module Oauth
  # Bearer-token identity document for the desktop GUI.
  class Userinfo
    def self.call(user)
      {
        sub: user.id.to_s,
        email: user.email,
        email_verified: user.confirmed?,
        name: user.display_name,
        customer_id: user.customer_id.to_s,
        role: user.primary_role_key
      }
    end
  end
end
