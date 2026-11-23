# frozen_string_literal: true

module Admin
  module Modules
    module Authentication
      # One already ordered, access-filtered domain projection as a collapsible
      # card; no record queries. A card holding a rejected Create Entry form
      # stays open so its modal can reopen with the errors.
      class UserDomainSectionComponent < ApplicationComponent
        attr_reader :section, :user, :customer_id, :id_prefix

        def initialize(section:, user:, customer_id:, id_prefix:, open: true)
          @section = section
          @user = user
          @customer_id = customer_id
          @id_prefix = id_prefix
          @open = open
        end

        def open? = @open || section.profiles.any? { |profile| profile.form&.errors&.any? }

        def self.section_id(section, id_prefix:)
          "#{id_prefix}-domain-#{section.domain&.id || 'other'}"
        end

        def self.title(section)
          section.domain&.name || I18n.t("admin_misc.domains.directory.ungrouped")
        end

        def self.dot_class(section)
          section.domain ? EntityDomainColors.dot(section.domain.color) : "bg-border-strong"
        end

        def section_id = self.class.section_id(section, id_prefix: id_prefix)
        def title = self.class.title(section)
        def description = section.domain&.description.presence
        def icon_path = EntitiesContributor::ICONS[section.domain ? :domain : :ungrouped]
        def tile_class
          section.domain ? "ring-1 ring-inset #{EntityDomainColors.tile(section.domain.color)}" : "bg-surface-active text-text-muted"
        end

        # A lone linked profile has no identity row, so its entry link sits
        # in the domain header instead.
        def header_profile
          profile = section.profiles.first
          profile if section.profiles.one? && profile.entry
        end

        def entry_path(profile) = helpers.admin_entity_entry_path(customer_id, profile.entity, profile.entry)

        def entry_label(profile)
          t("admin_modules.users.show.profiles.view_entry_label", entity: profile.entity.display_label, id: profile.entry.id)
        end
      end
    end
  end
end
