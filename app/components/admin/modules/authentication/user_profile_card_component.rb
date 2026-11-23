# frozen_string_literal: true

module Admin
  module Modules
    module Authentication
      # One profile row inside a domain card. A linked profile renders the
      # aggregator's visible fields (using its EntryDisplay) and association
      # rows as part of the user, with Add when the viewer may write them; a
      # missing one opens its Create Entry form, which creates the entry and
      # links it to +user+, in a modal that starts open only when the form
      # carries errors.
      class UserProfileCardComponent < ApplicationComponent
        include EntityAttributeGroupingHelper

        attr_reader :profile, :user, :customer_id, :id_prefix

        # +identity+ is the entity-name row. A domain section that holds one
        # linked profile omits it: the domain title already names the record.
        def initialize(profile:, user:, customer_id:, id_prefix:, identity: true)
          @profile = profile
          @user = user
          @customer_id = customer_id
          @id_prefix = id_prefix
          @identity = identity
        end

        def entity = profile.entity
        def entry = profile.entry
        def linked? = entry.present?
        def identity? = @identity
        def card_id = "#{id_prefix}-entity-#{entity.id}"
        def group_id(index) = "#{card_id}-group-#{index + 1}"
        def groups = profile.groups.reject { |group| group[:fields].empty? }
        def group_heading(group) = group[:heading].presence || t("admin_misc.entities.entry_detail.ungrouped")
        def associations = Array(profile.associations)
        def details? = groups.any? || associations.any?

        def group_card(group, index)
          Admin::Entities::AttributeGroupCardComponent.new(
            id: group_id(index), heading: group_heading(group), icon: group[:icon], color: group[:color],
            fields: group[:fields], entry: entry, display: profile.display, heading_tag: :h5, framed: false
          )
        end

        def association_section(section)
          UserProfileAssociationComponent.new(section: section, entity: entity, entry: entry, customer_id: customer_id,
                                              id_prefix: card_id, user: user, writable: profile.associations_writable)
        end

        def entry_path = helpers.admin_entity_entry_path(customer_id, entity, entry)
        def view_label = t("admin_modules.users.show.profiles.view_entry_label", entity: entity.display_label, id: entry.id)

        def form = profile.form
        def creatable? = !linked? && form.present?
        def form_open? = form.errors.any?
        def dialog_id = "#{card_id}-dialog"
        def dialog_title = t("admin_modules.users.show.profiles.create_title", entity: entity.display_label)

        def entry_form
          Admin::Entities::EntryFormComponent.new(
            form: form,
            url: helpers.admin_modules_authentication_user_profiles_path(customer_id, user, entity_id: entity.id),
            id_prefix: "#{card_id}-form",
            submit_label: t("admin_modules.users.show.profiles.create_profile"),
            dismiss_action: "modal-dialog#close"
          )
        end

        def missing_description
          key = if creatable? then "create_description"
                elsif !user.active? then "inactive_description"
                else "missing_description"
                end
          t("admin_modules.users.show.profiles.#{key}", entity: entity.display_label)
        end

        def tile_classes = EntityGlyph.text_class(EntityGlyph.color(entity))

        def tile_content
          icon = EntityGlyph.icon(entity)
          return attribute_group_icon(icon, css_class: "size-4") if icon

          EntityGlyph.monogram(entity.display_label).presence || attribute_group_icon("folder", css_class: "size-4")
        end

        def updated_at
          return tag.span(t("common.labels.em_dash"), class: "text-text-tertiary") if entry.updated_at.blank?

          tag.time(helpers.format_datetime(entry.updated_at), datetime: entry.updated_at.iso8601)
        end
      end
    end
  end
end
