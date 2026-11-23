# frozen_string_literal: true

module Admin
  module Modules
    module Authentication
      # Rows of one association of a linked profile entry (e.g. the courses a
      # student is enrolled in), rendered with the entry detail page's
      # association card. When +writable+, Add and Edit open the bridge-row
      # form in the page's quick-add dialog, and Edit and Delete carry a
      # return path so a full-page visit comes back to this user page.
      class UserProfileAssociationComponent < Admin::Entities::AssociationSectionComponent
        attr_reader :id_prefix, :user

        def initialize(section:, entity:, entry:, customer_id:, id_prefix:, user:, writable: false)
          super(section: section, entity: entity, entry: entry, customer_id: customer_id, writable: writable, framed: false)
          @id_prefix = id_prefix
          @user = user
        end

        def id = "#{id_prefix}-association-#{association.id}"
        def heading_tag = :h5
        def add_label = t("admin_misc.entities.association_entries.new_title", name: heading)
        def add_button_class = "min-h-11 w-full shrink-0 sm:min-h-9 sm:w-auto"

        def edit_path(row)
          helpers.edit_admin_entity_entry_association_entry_path(
            customer_id, entity, entry, association.id, row, return_to: return_path
          )
        end

        def destroy_path(row)
          helpers.admin_entity_entry_association_entry_path(
            customer_id, entity, entry, association.id, row, return_to: return_path
          )
        end

        def return_path
          helpers.admin_modules_authentication_user_path(customer_id, user, anchor: id)
        end
      end
    end
  end
end
