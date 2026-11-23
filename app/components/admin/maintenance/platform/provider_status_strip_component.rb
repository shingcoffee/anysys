# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      # Compact health / role / active-provider strip for nested vendor
      # settings pages. Action buttons (test connection) yield
      # into the trailing slot.
      class ProviderStatusStripComponent < ApplicationComponent
        def initialize(health_variant:, health_label:, role_active:,
                       role_active_label:, role_inactive_label:,
                       platform_value:,
                       health_caption:, role_caption:, platform_caption:)
          @health_variant = health_variant
          @health_label = health_label
          @role_active = role_active
          @role_active_label = role_active_label
          @role_inactive_label = role_inactive_label
          @platform_value = platform_value
          @health_caption = health_caption
          @role_caption = role_caption
          @platform_caption = platform_caption
        end

        attr_reader :health_variant, :health_label, :role_active,
                    :role_active_label, :role_inactive_label,
                    :platform_value,
                    :health_caption, :role_caption, :platform_caption

        def role_active? = !!role_active
      end
    end
  end
end
