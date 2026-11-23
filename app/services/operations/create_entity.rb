# frozen_string_literal: true

module Operations
  class CreateEntity < Base
    key "create_entity"
    version 3
    title "Create entity"
    summary "Create one or more related customer-owned entities atomically in an existing domain. Use for new entities only. Call create_domain first when starting a new sub-system. Associations, option sources, and aggregates may name other entities in the same call. Applies immediately."
    schema "create_entity.json"
    shared_defs "entity.defs.json"
    vocabulary EntityDefinitions::Api::Vocabulary
    annotations destructive: false, confirmation: :never

    register!

    def validate(input)
      Array.wrap(domain_missing(input["domain"])) +
        EntityDefinitions::Api::SemanticValidator.for_create(
          input.fetch("entities", []),
          customer: context.customer
        )
    end

    def plan(input)
      Array(input["entities"]).map do |spec|
        { "kind" => "entity", "action" => "created", "name" => spec["name"] }
      end
    end

    def perform(input)
      taken = names_taken(input)
      return Outcome.invalid(operation: self.class.key, violations: taken) if taken.any?

      domain = EntityDomain.find_by_name(context.customer.id, input["domain"])
      missing = domain_missing(input["domain"], domain: domain)
      return Outcome.invalid(operation: self.class.key, violations: [missing]) if missing

      mapper = EntityDefinitions::Api::Mapper.new(customer: context.customer)
      definitions = Array(input["entities"]).map { |spec| mapper.to_definition(spec) }
      signal, (ctx, *) = EntityDefinitions::Persist.call(
        { customer: context.customer, entities: definitions, create_only: true, domain: domain }
      )
      unless signal.to_h[:semantic] == :success
        return Outcome.invalid(
          operation: self.class.key,
          violations: [Violation.new(code: "domain.invalid", details: { "errors" => Array(ctx[:errors]) })]
        )
      end

      created = Array(ctx[:created]).map { |name| created_row(name) }
      Outcome.succeeded(
        operation: self.class.key,
        data: { "created" => created, "bridges" => Array(ctx[:bridges]), "domain" => domain.name },
        effects: created.map { |row| { "kind" => "entity", "action" => "created", "name" => row["name"] } }
      )
    end

    private

    def domain_missing(name, domain: :lookup)
      resolved = domain == :lookup ? EntityDomain.find_by_name(context.customer.id, name) : domain
      return if resolved

      Violation.new(pointer: "/domain", code: "entity_domain.not_found", details: { "name" => name.to_s })
    end

    # validate ran before the customer lock; perform runs under it, so a name
    # another writer took in between is caught here rather than merged into.
    def names_taken(input)
      Array(input["entities"]).each_with_index.filter_map do |spec, index|
        name = spec["name"].to_s.strip
        next unless Entity.unscope(where: :status).exists?(customer_id: context.customer.id, name: name)

        Violation.new(pointer: Pointer.join("/entities", index, "name"), code: "entity.already_exists",
                      details: { "name" => name })
      end
    end

    def created_row(name)
      entity = Entity.find_by!(customer_id: context.customer.id, name: name)
      {
        "name" => entity.name,
        "version" => entity.display_current_version&.version_number,
        "attributes" => public_attribute_summaries(entity)
      }
    end

    def public_attribute_summaries(entity)
      Array(entity.property_schema_json).filter_map do |attr|
        next unless attr.is_a?(Hash)
        next if attr["type"].to_s == Entity::ENTITY_REFERENCE_TYPE

        { "name" => attr["name"], "slug" => attr["name_slug"] }
      end
    end
  end
end
