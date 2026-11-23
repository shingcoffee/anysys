# frozen_string_literal: true

module Admin
  module Settings
    class MemberSurfaceFormComponent < ApplicationComponent
      attr_reader :presenter, :customer, :editable, :errors

      def initialize(presenter:, customer:, editable: true, errors: nil)
        @presenter = presenter
        @customer  = customer
        @editable = editable
        @errors = errors
      end

      def form_url
        "/#{customer.id}/admin/settings/member/sources/#{presenter.effective.source_key}/surfaces/#{presenter.surface_key}"
      end

      def name_for(field)       ; "member_settings[rows][0][#{field}]"   ; end
      def array_name_for(field) ; "member_settings[rows][0][#{field}][]" ; end

      def icon_options
        keys = ::Member::SidebarComponent::ICON_PATHS.keys.map(&:to_s)
        keys |= [presenter.icon] if presenter.icon.present?
        keys.map { |key| [I18n.t("settings_people.icons.#{key}", default: I18n.t("settings_people.saved_icon")), key] }
      end

      def back_path
        "/#{customer.id}/admin/settings/member/sources/#{presenter.effective.source_key}"
      end

      def entity_surface?
        presenter.effective.source_key.to_s == "entities"
      end

      def member_action_keys
        @member_action_keys ||= Page.active.launched.for_audience("member")
          .where(customer_id: [customer.id, nil])
          .where.not(action_key: [nil, ""])
          .distinct
          .order(:action_key)
          .pluck(:action_key)
      end

      def row_action_key_options
        keys = member_action_keys.dup
        current = overlay_value(:row_action_key)
        keys << current if current.present? && keys.exclude?(current)
        [[I18n.t("comp_admin.member_surface_form.row_action_none"), ""]] + keys.map { |key| [key, key] }
      end

      def overlay_value(key)
        settings = presenter.settings
        return "" unless settings.respond_to?(:config_json)

        json = settings.config_json
        json.is_a?(Hash) ? json[key.to_s].to_s : ""
      end

      def field_error?(field)
        field_messages(field).any?
      end

      def field_error_message(field)
        field_messages(field).first
      end

      def row_action_alert_message
        field_error_message(:row_action_key) ||
          field_error_message(:row_action_field) ||
          field_error_message(:row_action_label)
      end

      def row_action_select_html_options
        options = { id: "member-row-action-key", class: row_action_control_class(:row_action_key) }
        options[:aria] = { invalid: true } if field_error?(:row_action_key)
        options
      end

      def row_action_control_class(field, extras = "")
        ["input-field", extras, ("ring-danger" if field_error?(field))].compact_blank.join(" ")
      end

      private

      def field_messages(field)
        return [] if errors.blank?
        return [] unless errors.respond_to?(:[])

        Array(errors[field]).presence ||
          Array(errors[field.to_s]).presence ||
          Array(errors[field.to_sym]) ||
          []
      end
    end
  end
end
