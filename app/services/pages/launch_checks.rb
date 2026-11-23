# frozen_string_literal: true

module Pages
  # Launch checks that read beyond the page's own configuration: dropdowns
  # that would list nothing, required attributes missing from the form, and
  # ownership rules that keep member-owned records off public (and private
  # records off member) audiences. Fields are read through Page#input_fields,
  # so fields inside columns count. Tenant admins read these messages, so
  # none of them names the flowchart.
  class LaunchChecks
    PRIMARY_EXCLUDED_SOURCES = %w[base_model bridge identity].freeze
    DERIVED_TYPES = %w[Calculated Computed].freeze

    # Memoises what the checks read, so checking many pages costs one read
    # per distinct entity and dropdown rather than one per page.
    class Lookup
      ID = /\A\d+\z/

      attr_reader :customer_id

      def initialize(customer_id)
        @customer_id = customer_id
        @entities = {}
        @current_versions = {}
        @options = {}
        @compatibility = {}
      end

      # The page's entity under Page#entity's tenant rule.
      def entity_for(page)
        entity = entity(page.entity_id)
        return unless entity
        return entity if entity.shared?

        entity if !page.shared? && entity.customer_id == page.customer_id
      end

      # A shared entity or one of this tenant's own.
      def accessible_entity(id)
        entity = entity(id)
        entity if entity && (entity.shared? || entity.customer_id.to_s == customer_id.to_s)
      end

      # Flowcharts::Compatibility.errors, once per flowchart and entity.
      def compatibility_errors(flowchart, entity)
        return [] unless flowchart && entity

        @compatibility.fetch([flowchart.id, entity.id]) do
          @compatibility[[flowchart.id, entity.id]] = Flowcharts::Compatibility.errors(flowchart, entity)
        end
      end

      def current_version(entity)
        @current_versions.fetch(entity.id) do
          @current_versions[entity.id] = entity.resolved_current_version(customer_id)
        end
      end

      def reference_options(config, audience)
        key = [config["entity_id"].to_s, config["label_field"].to_s, audience.to_s]
        @options.fetch(key) do
          @options[key] = ::Entities::ReferenceOptions.new(
            entity_id: config["entity_id"], label_field: config["label_field"],
            customer_id: customer_id, audience: audience
          )
        end
      end

      private

      def entity(id)
        key = id.to_s
        return unless key.match?(ID)

        @entities.fetch(key) { @entities[key] = Entity.find_by(id: key) }
      end
    end

    def initialize(page, lookup: Lookup.new(page.customer_id || Current.customer_id))
      @page = page
      @lookup = lookup
    end

    # A dropdown whose target is gone lists nothing for anyone; one whose
    # display field an audience can't see lists nothing for that audience.
    def reference_errors(audiences = @page.visible_audiences)
      return [] if audiences.empty?

      reference_fields.flat_map do |field|
        config = field["dynamic_options"]
        next [message(:reference_target_inactive, field: field_label(field))] unless reference_target(config)

        audiences.filter_map do |audience|
          next if @lookup.reference_options(config, audience).usable?

          message(:reference_label_hidden, field: field_label(field), label: display_field_name(config),
                                           audience: audience_name(audience))
        end
      end
    end

    # Every attribute the contract requires for an audience must have a field,
    # on the entity itself and on each link the form collects. A page that
    # only edits records needs none: the contract keeps the stored value of
    # whatever the form doesn't post.
    def required_field_errors(audiences = @page.visible_audiences)
      entity = @lookup.entity_for(@page)
      return [] unless entity && @page.serves?(:create)

      own_field_errors(entity, audiences) + link_field_errors(entity, audiences)
    end

    # Problems that make every submission of the form fail.
    def submission_blockers
      processing_errors + required_field_errors
    end

    # The bound flowchart processes every submission, so it must exist, be
    # live, and name only attributes the page's entity has.
    def processing_errors
      errors = binding_errors
      return errors if errors.any?

      @lookup.compatibility_errors(@page.flowchart, @lookup.entity_for(@page))
    end

    # Ownership rules that depend on the audiences the form is offered to.
    # Takes an explicit list so a live page that just
    # gained an audience re-checks only the added ones.
    def audience_errors(audiences = @page.visible_audiences)
      audiences = Array(audiences).map(&:to_s)
      errors = []
      if audiences.any?
        errors.concat(public_kind_errors(audiences))
        errors.concat(private_reference_errors(audiences))
      end
      errors.concat(bridge_member_only_errors)
      errors
    end

    # Identity fields (source: identity) may only sit on a person-entity form.
    def identity_errors
      return [] unless @page.input_fields.any? { |field| FormParams.identity_field?(field) }
      return [] if @lookup.entity_for(@page)&.person?

      [message(:identity_field_not_person)]
    end

    # At most one active, launched page per action key and audience within
    # one owner (a customer's own pages, or the shared pages).
    def action_errors(audiences = @page.visible_audiences)
      key = @page.action_key.to_s
      return [] if key.blank?

      audiences = Array(audiences).map(&:to_s) & PageVisibility::AUDIENCES
      return [] if audiences.empty?

      audiences.filter_map do |audience|
        next unless colliding_page?(audience)

        message(:action_audience_taken, audience: audience_name(audience), action: key)
      end
    end

    # A page on a member-owned link entity: members only, or admins too when
    # the owner reference is a locked input. Re-checked on every save of a
    # live page, since dropping the input would otherwise go unnoticed.
    def bridge_member_only_errors
      entity = @lookup.entity_for(@page)
      return [] unless entity&.bridge_entity?
      return [] unless People::Ownership.kind(entity) == :owned
      return [] if @page.visible_audiences == [EntityAttributeAudience::MEMBER]
      return [] if owner_locked?(entity) && @page.visible_audiences.exclude?(EntityAttributeAudience::PUBLIC)

      [message(:bridge_page_member_only)]
    end

    private

    RESTRICTED_REFERENCE_KINDS = %i[person owned private nested].freeze
    BLOCKED_PUBLIC_KINDS = %i[owned private nested].freeze

    # An admin opens such a page only with the owner handed over from a run,
    # never by picking a member on a standalone form.
    def owner_locked?(entity)
      slug = People::Ownership.owner_reference(entity)&.slug
      slug.present? && @page.input_slugs.include?(slug)
    end

    def reference_fields
      @page.input_fields.select do |field|
        next if FormParams.identity_field?(field)

        field["dynamic_options"].is_a?(Hash) && field["dynamic_options"]["options_source"] == "entity_entries"
      end
    end

    def reference_target(config)
      @lookup.reference_options(config, EntityAttributeAudience::ADMIN).target
    end

    def display_field_name(config)
      slug = config["label_field"].to_s
      attribute = Array(reference_target(config)&.property_schema_json).grep(Hash).find { |attr| attr["name_slug"].to_s == slug }
      attribute&.dig("name").presence || slug
    end

    def own_field_errors(entity, audiences)
      present = slugs(@page.input_fields.reject { |field| PRIMARY_EXCLUDED_SOURCES.include?(field["source"].to_s) })
      missing_required(entity, audiences, present) do |attribute, audience|
        message(:required_field_missing, field: attribute_name(attribute), audience: audience_name(audience))
      end
    end

    def link_field_errors(entity, audiences)
      Array(entity.associations_json).grep(Hash).flat_map do |association|
        bridge = @lookup.accessible_entity(association["bridge_entity_id"])
        next [] unless bridge

        present = slugs(link_fields(bridge))
        next [] if present.empty?

        target = link_target_name(association)
        missing_required(bridge, audiences, present, skip: ->(attribute) { back_reference?(attribute, entity) }) do |attribute, audience|
          message(:required_link_field_missing, field: attribute_name(attribute), target: target, audience: audience_name(audience))
        end
      end
    end

    def missing_required(entity, audiences, present, skip: ->(_attribute) { false })
      attributes = Array(entity.property_schema_json).grep(Hash)
      audiences.flat_map do |audience|
        attributes.filter_map do |attribute|
          next unless required_for?(attribute, audience)
          next if skip.call(attribute) || present.include?(attribute["name_slug"].to_s)
          next if owner_filled_for?(entity, attribute, audience)

          yield attribute, audience
        end
      end
    end

    # FormParams hides the owner reference from members and does not require
    # it — the submit boundary fills it. Reuse that rule so launch and submit
    # stay in lockstep.
    def owner_filled_for?(entity, attribute, audience)
      return false unless audience.to_s == EntityAttributeAudience::MEMBER

      slug = attribute["name_slug"].to_s
      return false unless People::Ownership.owner_reference(entity)&.slug == slug

      field = { "property_slug" => slug, "id" => slug }
      primary = @lookup.entity_for(@page)
      if primary && entity.id.to_s != primary.id.to_s
        field["source"] = "bridge"
        field["source_section"] = entity.id.to_s
      end
      !FormParams.new(page: @page, entity: primary || entity, params: {}, audience: audience).required_field?(field)
    end

    def colliding_page?(audience)
      scope = Page.where(action_key: @page.action_key, launched: true, customer_id: @page.customer_id)
                  .for_audience(audience)
      scope = scope.where.not(id: @page.id) if @page.persisted?
      scope.exists?
    end

    def public_kind_errors(audiences)
      return [] unless audiences.include?(EntityAttributeAudience::PUBLIC)

      blocked_entities.filter_map do |entity|
        next unless BLOCKED_PUBLIC_KINDS.include?(People::Ownership.kind(entity))

        message(:owned_entity_public_audience, entity: entity_label(entity))
      end
    end

    def blocked_entities
      entity = @lookup.entity_for(@page)
      return [] unless entity

      [entity] + carried_bridge_entities(entity)
    end

    def carried_bridge_entities(entity)
      Array(entity.associations_json).grep(Hash).filter_map do |association|
        bridge = @lookup.accessible_entity(association["bridge_entity_id"])
        next unless bridge
        next if link_fields(bridge).empty?

        bridge
      end
    end

    def private_reference_errors(audiences)
      reference_targets.flat_map do |field, target|
        kind = People::Ownership.kind(target)
        audiences.filter_map do |audience|
          next unless restricted_for_audience?(kind, audience)

          message(:reference_private_for_audience, field: field_label(field),
                                                   target: entity_label(target),
                                                   audience: audience_name(audience))
        end
      end
    end

    def restricted_for_audience?(kind, audience)
      case audience
      when EntityAttributeAudience::PUBLIC then RESTRICTED_REFERENCE_KINDS.include?(kind)
      when EntityAttributeAudience::MEMBER then kind == :private
      else false
      end
    end

    def reference_targets
      @page.input_fields.filter_map do |field|
        next if PRIMARY_EXCLUDED_SOURCES.include?(field["source"].to_s)

        target = target_for_reference_field(field)
        [field, target] if target
      end
    end

    def target_for_reference_field(field)
      config = field["dynamic_options"]
      if config.is_a?(Hash) && config["options_source"] == "entity_entries"
        return reference_target(config) || @lookup.accessible_entity(config["entity_id"])
      end

      attribute = bound_attribute(field)
      return unless attribute

      target_id =
        if attribute["type"] == Entity::ENTITY_REFERENCE_TYPE
          attribute["entity_id"]
        elsif Entities::ReferenceLabels.reference?(attribute)
          attribute.dig("config", "entity_id")
        end
      @lookup.accessible_entity(target_id)
    end

    def bound_attribute(field)
      entity = field_entity(field)
      return unless entity

      slug = field["property_slug"].to_s
      Array(entity.property_schema_json).grep(Hash).find { |attribute| attribute["name_slug"].to_s == slug }
    end

    def field_entity(field)
      primary = @lookup.entity_for(@page)
      return unless primary
      return primary unless field["source"].to_s == "bridge"

      Array(primary.associations_json).grep(Hash).each do |association|
        bridge = @lookup.accessible_entity(association["bridge_entity_id"])
        next unless bridge

        return bridge if [bridge.id.to_s, bridge.name.to_s].include?(field["source_section"].to_s)
      end
      nil
    end

    def entity_label(entity)
      entity.display_label.presence || entity.name
    end

    # The contract's rule: a presence or acceptance validator that applies to
    # the audience. Defaults don't count, because submissions don't apply them.
    def required_for?(attribute, audience)
      return false if attribute["name_slug"].blank? || derived?(attribute)

      requiring = Array(attribute["validators"]).any? do |validator|
        validator.is_a?(Hash) && ValidatorRegistry::REQUIRING_VALIDATIONS.include?(validator["type"].to_s.to_sym)
      end
      requiring && EntityAttributeAudience.applying_audiences(attribute).include?(audience)
    end

    def derived?(attribute)
      DERIVED_TYPES.include?(attribute["type"]) || attribute["storage"] == "computed"
    end

    def link_fields(bridge)
      sections = [bridge.id.to_s, bridge.name.to_s]
      @page.input_fields.select { |field| field["source"] == "bridge" && sections.include?(field["source_section"].to_s) }
    end

    # Pages::BridgeEntries fills in the link's reference to the new entry.
    def back_reference?(attribute, entity)
      attribute["type"] == Entity::ENTITY_REFERENCE_TYPE && attribute["entity_id"].to_s == entity.id.to_s
    end

    def link_target_name(association)
      @lookup.accessible_entity(association["target_entity_id"])&.display_label.presence ||
        association["target_entity_name"].to_s
    end

    def slugs(fields)
      fields.map { |field| field["property_slug"].to_s }.to_set
    end

    def field_label(field)
      field["label"].presence || field["property_slug"].to_s
    end

    def attribute_name(attribute)
      attribute["name"].presence || attribute["name_slug"].to_s
    end

    def audience_name(audience)
      I18n.t("common.visibility.#{audience}")
    end

    def message(key, **vars)
      I18n.t("maint_core.errors.page_launch.#{key}", **vars)
    end

    def binding_errors
      flowchart = @page.flowchart
      return [message(:submission_process_missing)] unless flowchart
      return [message(:submission_process_offline)] unless flowchart.launched?

      []
    end
  end
end
