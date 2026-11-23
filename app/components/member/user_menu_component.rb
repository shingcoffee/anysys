# frozen_string_literal: true

module Member
  class UserMenuComponent < ApplicationComponent
    include UsesSiteChrome
    def initialize(customer:, user:)
      @customer = customer
      @user     = user
    end

    attr_reader :customer, :user

    def initials
      "#{user.first_name.to_s[0]}#{user.last_name.to_s[0]}".upcase
    end

    def profile_path
      "/#{customer.id}/member/profile"
    end

    def security_path
      "/#{customer.id}/member/security"
    end

    def sign_out_path
      "/auth/sign_out"
    end
  end
end
