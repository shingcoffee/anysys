# frozen_string_literal: true

module Admin
  module Entities
    # Account card on a person-entity entry detail: the same-tenant user this
    # entry extends, with a way to their user detail page, or a picker when
    # none is connected yet. A connected account is the entry's own user, so
    # the card does not announce a separate link.
    # The picker Stimulus controller mounts only when the entry is writable
    # and not yet linked.
    class PersonLinkComponent < ApplicationComponent
      attr_reader :entity, :entry, :user

      def initialize(entity:, entry:, user:, writable:)
        @entity = entity
        @entry = entry
        @user = user
        @writable = writable
      end

      def writable? = @writable
      def linked? = user.present?
      def picker? = writable? && !linked?
      def inactive? = linked? && user.inactive?

      def linked_name
        user.full_name.presence || user.display_name
      end

      def initials = EntityGlyph.monogram(linked_name)

      def link_path
        helpers.admin_entity_entry_person_link_path(entry.customer_id, entity, entry)
      end

      def candidates_url
        helpers.candidates_admin_entity_entry_person_link_path(
          entry.customer_id, entity, entry, format: :json
        )
      end

      def panel_id = "person-link-panel-#{entry.id}"
      def list_id = "person-link-list-#{entry.id}"

      def user_path
        helpers.admin_modules_authentication_user_path(entry.customer_id, user)
      end

      def section_data
        return {} unless picker?

        {
          controller: "person-link-picker",
          person_link_picker_candidates_url_value: candidates_url,
          person_link_picker_type_to_search_label_value: t("comp_admin.person_link.type_to_search"),
          person_link_picker_loading_label_value: t("comp_admin.person_link.searching"),
          person_link_picker_empty_label_value: t("comp_admin.person_link.empty"),
          person_link_picker_error_label_value: t("comp_admin.person_link.error"),
          person_link_picker_confirm_template_value: t("comp_admin.person_link.confirm_body")
        }
      end
    end
  end
end
