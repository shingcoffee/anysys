# frozen_string_literal: true

module Admin
  module Settings
    class RolePresenter
      RESERVED_KEYS = %w[owner admin member].freeze

      def initialize(role)
        @role = role
      end

      def name
        reserved? ? I18n.t("settings_people.#{@role.key}_name") : @role.name
      end

      def scope
        I18n.t("settings_people.#{reserved? ? @role.key : 'custom'}_scope")
      end

      def kind
        I18n.t(@role.system? ? "settings_people.built_in_role" : "settings_people.custom_role")
      end

      private

      def reserved?
        RESERVED_KEYS.include?(@role.key)
      end
    end
  end
end
