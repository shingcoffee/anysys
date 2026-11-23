# frozen_string_literal: true

module Member
  # Shell for /:cid/member/* pages. Sticky top bar, mobile sheet, and
  # footer in the customer's public website theme — the same chrome as
  # /:cid/site.
  class ShellComponent < ApplicationComponent
    CONTAINER_CLASSES = {
      default: "w-full max-w-7xl mx-auto min-w-0 px-5 sm:px-8 lg:px-12",
      narrow:  "w-full max-w-3xl mx-auto min-w-0 px-5 sm:px-8 lg:px-12",
      edge:    "w-full min-w-0"
    }.freeze

    def initialize(customer:, user:, current_nav:, container_width: :default)
      unless CONTAINER_CLASSES.key?(container_width)
        raise ArgumentError,
              "Unknown container_width: #{container_width.inspect} (expected one of #{CONTAINER_CLASSES.keys.inspect})"
      end

      @customer        = customer
      @user            = user
      @current_nav     = current_nav
      @container_width = container_width
    end

    attr_reader :customer, :user, :current_nav, :container_width

    def container_classes
      CONTAINER_CLASSES.fetch(container_width)
    end

    def nav_items
      Member::Navigation.items_for(user)
    end

    def home_path
      "/#{customer.id}/member"
    end

    def chrome
      @chrome ||= Member::Chrome.new(helpers.member_site_theme)
    end

    def current?(item)
      item.key == current_nav
    end
  end
end
