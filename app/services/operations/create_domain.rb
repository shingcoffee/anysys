# frozen_string_literal: true

module Operations
  class CreateDomain < Base
    key "create_domain"
    version 1
    title "Create domain"
    summary "Start a new sub-system: a named group of related entities in this workspace. Call this before create_entity when the catalog has no domain for that business area. Does not create entities. Applies immediately."
    schema "create_domain.json"
    annotations destructive: false, confirmation: :never

    register!

    def validate(input)
      Array.wrap(already_exists_violation(input["name"]))
    end

    def plan(input)
      [{ "kind" => "domain", "action" => "created", "name" => input["name"].to_s.strip }]
    end

    def perform(input)
      name = input["name"].to_s.strip
      existing = already_exists_violation(name)
      return Outcome.invalid(operation: self.class.key, violations: [existing]) if existing

      result = EntityDomains::Activities::Save.call(
        domain: EntityDomain.new(customer_id: context.customer.id),
        params: save_params(input, name),
        customer_id: context.customer.id
      )
      unless result.success?
        raced = already_exists_violation(name)
        return Outcome.invalid(operation: self.class.key, violations: [raced]) if raced

        return Outcome.invalid(operation: self.class.key, violations: save_failures(result, name))
      end

      domain = result.model
      Outcome.succeeded(
        operation: self.class.key,
        data: {
          "domain" => {
            "name" => domain.name,
            "description" => domain.description,
            "color" => domain.color
          }
        },
        effects: [{ "kind" => "domain", "action" => "created", "name" => domain.name }]
      )
    end

    private

    def already_exists_violation(name)
      key = name.to_s.strip
      return unless EntityDomain.find_by_name(context.customer.id, key)

      Violation.new(pointer: "/name", code: "entity_domain.already_exists", details: { "name" => key })
    end

    def save_params(input, name)
      params = { "name" => name }
      params["description"] = input["description"] if input.key?("description")
      params["color"] = input["color"] if input.key?("color")
      params
    end

    def save_failures(result, name)
      Array(result.errors).flat_map do |attribute, _messages|
        pointer = Pointer.join("/", attribute)
        if attribute.to_s == "name"
          [Violation.new(pointer: pointer, code: "entity_domain.already_exists", details: { "name" => name })]
        else
          [Violation.new(pointer: pointer, code: "schema.invalid", details: { "name" => name })]
        end
      end.presence || [Violation.new(code: "internal.error")]
    end
  end
end
