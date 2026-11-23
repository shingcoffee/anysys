# frozen_string_literal: true

require_relative "navigation/item"

module Member
  module Navigation
    # Hidden from the top nav because the user menu already exposes them.
    # They remain reachable by direct URL and from that menu.
    HIDDEN_FROM_NAV = %i[builtin_profile builtin_security].freeze

    def self.items_for(user)
      Member::Surfaces
        .for(customer: user.customer)
        .map { |effective| item_from_effective(effective) }
        .select { |item| item.visible_to?(user) }
        .reject { |item| HIDDEN_FROM_NAV.include?(item.key) }
    end

    def self.item_from_effective(effective)
      descriptor = effective.descriptor

      if descriptor.respond_to?(:path_seg)
        Item.new(
          key:     effective.key,
          label:   effective.label,
          icon:    effective.icon,
          path:    ->(customer) {
            seg = descriptor.path_seg.to_s
            seg.empty? ? "/#{customer.id}/member" : "/#{customer.id}/member/#{seg}"
          },
          visible: ->(user) { effective.enabled_for?(user) }
        )
      else
        Item.new(
          key:     effective.key,
          label:   effective.label,
          icon:    effective.icon,
          path:    ->(customer) { "/#{customer.id}/member/#{effective.key}" },
          visible: ->(user) { effective.enabled_for?(user) }
        )
      end
    end
  end
end
