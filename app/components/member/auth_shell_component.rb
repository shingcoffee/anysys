# frozen_string_literal: true

module Member
  # Split-pane shell for /:cid/auth/* surfaces (sign-in, sign-up, password
  # recovery). Warm brand pane on the left, form on the right, both inside one
  # centered card. Mobile stacks the brand pane above the form.
  class AuthShellComponent < ApplicationComponent
    def initialize(customer:, title:, subtitle:)
      @customer = customer
      @title    = title
      @subtitle = subtitle
    end

    attr_reader :customer, :title, :subtitle

    def brand_name
      customer&.name.presence || t("member.auth_shell.portal_name")
    end
  end
end
