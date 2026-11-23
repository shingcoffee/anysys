# frozen_string_literal: true

module Admin
  module Maintenance
    module Entities
      # Entities index for the platform owner, one domain (sub-system) at a
      # time: a domain rail with entity and journey counts, then the selected
      # domain's header, its entities and its journeys. Shared entities the
      # customer has not placed get a trailing "Not in a domain" rail entry.
      class DomainWorkspaceComponent < ApplicationComponent
        FRAME_ID = "entity-domains"
        UNGROUPED = "ungrouped"
        KIND_FILTERS = [nil, *EntityDomains::Layout::KINDS].freeze
        DOMAIN_ICON = EntitiesContributor::ICONS[:domain]

        attr_reader :customer_id, :query, :kind

        def initialize(sections:, journeys:, customer_id:, selected: nil, query: nil, kind: nil)
          @sections = Array(sections)
          @journeys = Array(journeys).group_by(&:entity_domain_id)
          @customer_id = customer_id
          @selected = selected.to_s.presence
          @query = query.to_s.strip
          @kind = EntityDomains::Layout::KINDS.include?(kind.to_s) ? kind.to_s : nil
        end

        def frame_id = FRAME_ID

        def domain_sections = @domain_sections ||= @sections.reject(&:ungrouped?)
        def rail_sections = domain_sections + Array(@sections.find(&:ungrouped?))
        def no_domains? = domain_sections.empty?

        # The selected section, the first domain when none is chosen, or nil
        # when the chosen one no longer exists.
        def current
          return @current if defined?(@current)

          @current = @selected ? rail_sections.find { |section| key(section) == @selected } : rail_sections.first
        end

        def domain = current&.domain
        def key(section) = section.ungrouped? ? UNGROUPED : section.domain.id.to_s
        def active?(section) = section.equal?(current)

        def title(section)
          section.ungrouped? ? t("maint_core.entity_domains.workspace.not_in_domain") : section.domain.name
        end

        def dot_class(section)
          section.ungrouped? ? "bg-warning" : EntityDomainColors.dot(section.domain.color)
        end

        def tile_class = EntityDomainColors.tile(domain.color)

        def journeys_for(section) = section.ungrouped? ? [] : @journeys.fetch(section.domain.id, [])

        def rail_meta(section)
          parts = [t("maint_core.entity_domains.index.entity_count", count: section.items.size)]
          unless section.ungrouped?
            parts << t("maint_core.entity_domains.workspace.journey_count", count: journeys_for(section).size)
          end
          parts.join(" · ")
        end

        def stats
          bridges = current.items.count { |item| item.entity.bridge_entity? }
          [
            t("maint_core.entity_domains.index.entity_count", count: current.items.size - bridges),
            t("maint_core.entity_domains.workspace.bridge_count", count: bridges),
            t("maint_core.entity_domains.workspace.journey_count", count: journeys_for(current).size)
          ]
        end

        def entities
          @entities ||= current.items.map(&:entity).select { |entity| matches?(entity) }
        end

        def filtered? = query.present? || kind.present?

        def kind_filters
          KIND_FILTERS.map do |value|
            { label: t("maint_core.entity_domains.index.kinds.#{value || 'all'}"),
              path: filter_path(kind: value), active: value == kind }
          end
        end

        # Index URL keeping the current domain, search and kind unless overridden.
        def filter_path(**overrides)
          state = { domain_id: (key(current) if current), q: query.presence, kind: kind }.merge(overrides).compact
          helpers.admin_maintenance_entities_path(customer_id, state)
        end

        def rail_path(section) = filter_path(domain_id: key(section), q: nil, kind: nil)

        def new_domain_path = helpers.new_admin_maintenance_entity_domain_path(customer_id)
        def edit_domain_path = helpers.edit_admin_maintenance_entity_domain_path(customer_id, domain)
        def new_entity_path = helpers.new_admin_maintenance_entity_path(customer_id, domain_id: domain.id)
        def new_journey_path = helpers.new_admin_maintenance_journey_path(customer_id, domain_id: domain.id)
        def generate_journey_path = helpers.generate_admin_maintenance_journeys_path(customer_id, domain_id: domain.id)

        def kind_badge(entity)
          entity.bridge_entity? ? [:info, t("common.labels.bridge")] : [:default, t("common.labels.normal")]
        end

        def entity_tile_class(entity)
          entity.bridge_entity? ? "bg-info-subtle text-info" : "bg-accent-subtle text-accent-text"
        end

        def subtitle(entity) = entity.description.presence || entity.name
        def attributes_count(entity) = Array(entity.property_schema_json).length

        def version_label(entity)
          version = entity.display_current_version
          version ? "v#{version.version_number}" : t("common.labels.em_dash")
        end

        def updated_text(entity)
          t("chrome.admin_table.time_ago", time: helpers.time_ago_in_words(entity.updated_at))
        end

        def updated_exact(entity) = I18n.l(entity.updated_at, format: :long)

        def entity_path(entity) = helpers.admin_maintenance_entity_path(customer_id, entity)
        def edit_entity_path(entity) = helpers.edit_admin_maintenance_entity_path(customer_id, entity)

        def entity_menu(entity)
          items = [
            { label: t("maint_core.nav.versions"), path: "#",
              data: { turbo: "false", action: "versions#open", "versions-id-param": entity.id,
                      "versions-name-param": entity.display_label } },
            { label: t("maint_core.entity_domains.index.move"),
              path: helpers.edit_admin_maintenance_entity_domain_membership_path(customer_id, entity) }
          ]
          if helpers.can_copy_definition?(entity)
            items << { label: t("common.actions.copy"), path: helpers.admin_maintenance_entity_copy_path(customer_id, entity) }
          end
          if helpers.can_destroy_definition?(entity)
            items << :separator
            items << { label: t("common.actions.delete"), path: entity_path(entity), method: :delete, tone: :danger,
                       data: { turbo_confirm: t("maint_core.entities.index.delete_confirm", name: entity.display_label) } }
          end
          items
        end

        private

        def matches?(entity)
          return false if kind && (kind == "bridge") != entity.bridge_entity?
          return true if query.empty?

          needle = query.downcase
          [entity.display_label, entity.name].any? { |text| text.to_s.downcase.include?(needle) }
        end
      end
    end
  end
end
