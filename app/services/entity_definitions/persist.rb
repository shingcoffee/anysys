# frozen_string_literal: true

module EntityDefinitions
  # Persists a related set of customer-owned entity definitions for one tenant.
  # Entities it creates go into `domain` (required for a create), and new
  # bridges join the domain of the entity that declares them.
  class Persist < Trailblazer::Activity::Railway
    step :require_customer
    step :normalize_definitions
    step :persist_set

    def require_customer(ctx, customer: nil, **)
      ctx[:customer] = customer.presence || Current.customer
      ctx[:errors] = []
      return true if ctx[:customer]

      ctx[:errors] << I18n.t("ai_assistant.assistant.apply_errors.no_customer")
      false
    end

    def normalize_definitions(ctx, entities:, **)
      result = Normalizer.call(entities)
      ctx[:definitions] = result.definitions
      ctx[:errors] = result.errors
      result.ok?
    end

    def persist_set(ctx, definitions:, customer:, replace: false, create_only: false, domain: nil, **)
      writer = Writer.new(definitions, customer: customer, replace: replace, create_only: create_only, domain: domain)
      Current.with_customer(customer) { writer.run }
      ctx[:created] = writer.created
      ctx[:updated] = writer.updated
      ctx[:bridges] = writer.bridges
      ctx[:errors] = writer.errors
      writer.errors.empty?
    rescue Writer::Failed => e
      ctx[:created] = []
      ctx[:updated] = []
      ctx[:bridges] = []
      ctx[:errors] = e.messages
      false
    rescue ActiveRecord::RecordNotUnique
      ctx[:created] = ctx[:updated] = ctx[:bridges] = []
      ctx[:errors] = [I18n.t("ai_assistant.assistant.update_needs_confirmation")]
      false
    end

    # Writes definitions inside one transaction. Raises Failed to roll back.
    #
    # The assignment phase lives in DefinitionAssignment because the
    # assistant's change plan replays it on an unsaved copy to predict this
    # write. Anything moved out of there and back into this class stops being
    # part of what the admin reviews.
    class Writer
      include DefinitionAssignment

      class Failed < StandardError
        attr_reader :messages

        def initialize(messages)
          @messages = Array(messages)
          super(@messages.join(" "))
        end
      end

      attr_reader :created, :updated, :bridges, :errors

      def initialize(definitions, customer:, replace: false, create_only: false, domain: nil)
        @definitions = definitions
        @customer = customer
        @domain = domain
        @replace = replace
        @create_only = create_only
        @created = []
        @updated = []
        @bridges = []
        @errors = []
        @records = {}
        @computed_attrs = {}
        @computed_slots = {}
        @incoming_groups = {}
      end

      def run
        @customer.with_lock(requires_new: true) do
          persist_identities
          persist_option_sources
          persist_associations
          persist_computed
        end
        true
      end

      private

      def fail!(messages)
        raise Failed, messages
      end

      def tenant_id
        @customer.id
      end

      def persist_identities
        @definitions.each do |definition|
          name = definition["name"].to_s.strip
          fail!(I18n.t("ai_assistant.assistant.apply_errors.name_blank")) if name.blank?

          record = find_existing(name)
          if record.nil?
            create_entity!(definition, name)
          elsif @create_only
            # A name taken after the caller validated must not turn a create
            # into an unreviewed update of someone else's entity.
            fail!(I18n.t("operations.violations.entity.already_exists", name: name))
          else
            update_entity!(record, definition, name)
          end
        end
      end

      def find_existing(name)
        Entity.unscope(where: :status).where(customer_id: tenant_id, name: name).lock.first
      end

      def create_entity!(definition, name)
        unless @domain&.customer_id == tenant_id
          fail!(I18n.t("ai_assistant.assistant.apply_errors.domain_required", name: name))
        end
        guard = Billing::Quota::Guard.check(customer: @customer, item_key: "entity")
        fail!(guard.message) unless guard.allowed?

        record = Entity.new
        assign_identity(record, definition, name)
        assign_definition_body(record, definition, name)
        save_entity!(record)
        EntityDomains::Memberships.place!(record, @domain)
        @created << record.name
        @records[name] = record
      end

      def update_entity!(record, definition, name)
        if record.inactive?
          fail!(I18n.t("ai_assistant.assistant.apply_errors.inactive", name: name))
        end
        if record.bridge_entity?
          fail!(I18n.t("ai_assistant.assistant.apply_errors.bridge_not_authorable"))
        end
        unless record.customer_owned? && record.customer_id == tenant_id
          fail!(I18n.t("ai_assistant.assistant.apply_errors.forbidden_identity"))
        end

        assign_identity(record, definition, name)
        assign_definition_body(record, definition, name)
        save_entity!(record)
        @updated << record.name
        @records[name] = record
      end

      # The record mutation itself is shared with the change plan; what stays
      # here is the bookkeeping the second pass needs.
      def assign_definition_body(record, definition, name)
        body = assign_body(record, definition, replace: @replace)
        @computed_attrs[name] = body.computed_attributes
        @computed_slots[name] = body.computed_slots
        @incoming_groups[name] = body.incoming_groups
      end

      def save_entity!(record)
        fail!(record.errors.full_messages) unless record.save
      end

      # A choice attribute may draw its list from another entity's entries. The
      # definition names that entity; the id is resolved here, once every
      # identity in the batch exists, so the LLM never handles a record id.
      def persist_option_sources
        @records.each_value do |record|
          schema = Array(record.property_schema_json)
          next unless schema.any? { |attr| dynamic_options?(attr) }

          record.property_schema_json = schema.map do |attr|
            dynamic_options?(attr) ? attr.merge("config" => resolved_option_source(attr)) : attr
          end
          save_entity!(record)
        end
      end

      def dynamic_options?(attr)
        attr.is_a?(Hash) && attr.dig("config", ChoiceList::ENTITY_NAME_KEY).present?
      end

      def resolved_option_source(attr)
        config = attr["config"].to_h
        target_name = config[ChoiceList::ENTITY_NAME_KEY].to_s.strip
        target = resolve_entity(target_name)
        fail!(I18n.t("ai_assistant.assistant.apply_errors.target_not_found", name: target_name)) if target.nil?

        config.except(ChoiceList::ENTITY_NAME_KEY, "options").merge(
          "options_source" => Capabilities::ENTITY_ENTRIES_OPTIONS_SOURCE,
          ChoiceList::ENTITY_ID_KEY => target.id.to_s
        )
      end

      def persist_associations
        @definitions.each do |definition|
          next unless definition.key?("associations")

          name = definition["name"].to_s.strip
          record = @records[name]
          fail!(I18n.t("ai_assistant.assistant.apply_errors.target_not_found", name: name)) if record.nil?

          record.associations_json = carry_bridges(
            record.associations_list,
            stored_associations(record, definition["associations"])
          )
          save_entity!(record)
          fail!(record.errors[:associations].presence || record.errors.full_messages) unless record.sync_bridge_entities!
          record.reload
          EntityDomains::Memberships.place_bridges!(record)
          @records[record.name] = record
          Array(record.associations_list).each do |assoc|
            @bridges << assoc["bridge_entity_name"] if assoc["bridge_entity_name"].present?
          end
        end
        @bridges.uniq!
      end

      def resolve_entity(name)
        return nil if name.blank?

        @records[name] || Entity.where(customer_id: tenant_id).non_bridge.find_by(name: name)
      end

      def persist_computed
        @computed_attrs.each do |name, computed_attrs|
          next if computed_attrs.blank?

          record = @records[name] || Entity.where(customer_id: tenant_id).find_by(name: name)
          fail!(I18n.t("ai_assistant.assistant.apply_errors.target_not_found", name: name)) if record.nil?

          resolved = computed_attrs.map { |field| resolve_computed(record, field) }
          record.property_schema_json = if @replace
            reinsert_computed(record.property_schema_json, resolved, @computed_slots[name])
          else
            merge_attributes(record.property_schema_json, resolved)
          end
          apply_grouping!(record, @incoming_groups[name], replace: @replace)
          save_entity!(record)
        end
      end
    end
  end
end
