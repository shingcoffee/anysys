# frozen_string_literal: true

module Operations
  class UpdateEntity < Base
    key "update_entity"
    version 2
    title "Update entity"
    summary "Change existing customer-owned entities with a typed editor change set. Always waits for administrator approval. Read with get_entity first and pass expected_version. Do not claim the change is applied until the admin confirms."
    schema "update_entity.json"
    shared_defs "entity.defs.json"
    vocabulary EntityDefinitions::Api::Vocabulary
    annotations destructive: true, confirmation: :always
    insert_defaults false

    register!

    def validate(input)
      applied, violations = prepare(input)
      semantic = if applied.any?
        EntityDefinitions::Api::SemanticValidator.for_update(
          applied.map { |row| row[:document] },
          customer: context.customer,
          origins: applied.map { |row| row[:origins] }
        )
      else
        []
      end
      (violations + semantic).first(Operations::Schema::MAX_VIOLATIONS)
    end

    def plan(input)
      applied, = prepare(input)
      return [] if applied.empty?

      EntityDefinitions::Assistant::ChangePlan.call(
        entities: applied.map { |row| row[:document] },
        customer: context.customer,
        replace: true
      ).as_json
    end

    def snapshot(input)
      Array(input["updates"]).each_with_object({}) do |update, acc|
        record = editable_record(update["entity"])
        acc[update["entity"].to_s] = record&.current_line_head_version_id
      end
    end

    def stale?(snapshot)
      return true unless snapshot.is_a?(Hash)

      snapshot.stringify_keys.any? do |name, version_id|
        record = editable_record(name)
        record.nil? || record.current_line_head_version_id != version_id
      end
    end

    def perform(input)
      mapper = EntityDefinitions::Api::Mapper.new(customer: context.customer)
      documents = {}
      Array(input["updates"]).each_with_index do |update, index|
        doc = EntityDefinitions::Api::SemanticValidator.catalog_document(context.customer, update["entity"])
        result = EntityDefinitions::Api::ChangeSet.apply(
          doc,
          update["changes"],
          mapper: mapper,
          pointer_prefix: Pointer.join("/updates", index, "changes")
        )
        documents[update["entity"]] = result.document
      end

      signal, (ctx, *) = EntityDefinitions::Persist.call(
        { customer: context.customer, entities: documents.values, replace: true }
      )
      unless signal.to_h[:semantic] == :success
        return Outcome.invalid(
          operation: self.class.key,
          violations: [Violation.new(code: "domain.invalid", details: { "errors" => Array(ctx[:errors]) })]
        )
      end

      updated = Array(ctx[:updated]).map { |name| updated_row(name) }
      Outcome.succeeded(
        operation: self.class.key,
        data: { "updated" => updated, "bridges" => bridges_for(documents.keys) },
        effects: updated.map { |row| { "kind" => "entity", "action" => "updated", "name" => row["name"] } }
      )
    end

    private

    def prepare(input)
      mapper = EntityDefinitions::Api::Mapper.new(customer: context.customer)
      applied = []
      violations = []

      seen = Set.new
      Array(input["updates"]).each_with_index do |update, index|
        name = update["entity"].to_s
        pointer = Pointer.join("/updates", index, "entity")
        # Two change sets for one entity would be planned separately and then
        # both dropped by the writer, so the admin would approve a no-op.
        unless seen.add?(name)
          violations << Violation.new(pointer: pointer, code: "entity.duplicate_in_request", details: { "name" => name })
          next
        end

        target = EntityDefinitions::Api::SemanticValidator.locate(customer: context.customer, name: name)
        violation = target.violation(name: name, pointer: pointer)
        if violation
          violations << violation
          next
        end

        # expected_version guards the model's read. On approval the parked
        # snapshot (head version ids) is the stricter check, and Confirm runs it.
        if update["expected_version"] && !context.confirmed &&
           target.record.display_current_version&.version_number != update["expected_version"].to_i
          violations << Violation.new(
            pointer: Pointer.join("/updates", index, "expected_version"),
            code: "conflict.version_changed",
            details: {
              "expected" => update["expected_version"],
              "got" => target.record.display_current_version&.version_number
            }
          )
          next
        end

        doc = EntityDefinitions::Api::SemanticValidator.catalog_document(context.customer, name)
        result = EntityDefinitions::Api::ChangeSet.apply(
          doc,
          update["changes"],
          mapper: mapper,
          pointer_prefix: Pointer.join("/updates", index, "changes")
        )
        violations.concat(result.violations)
        applied << { document: result.document, origins: result.origins }
      end

      [applied, violations]
    end

    def editable_record(name)
      Entity.where(customer_id: context.customer.id).non_bridge.find_by(name: name)
    end

    def updated_row(name)
      entity = Entity.find_by!(customer_id: context.customer.id, name: name)
      {
        "name" => entity.name,
        "version" => entity.display_current_version&.version_number
      }
    end

    def bridges_for(names)
      Array(names).flat_map do |name|
        entity = Entity.find_by(customer_id: context.customer.id, name: name)
        next [] unless entity

        Array(entity.associations_list).filter_map { |assoc| assoc["bridge_entity_name"] }
      end.uniq
    end
  end
end
