# frozen_string_literal: true

# Use the checked E2E runner and normal model/version callbacks. Every invocation
# owns exact UUID-named records; the bootstrap's mention/runtime fixtures are read
# only, including during cleanup.
module BuilderBrowserFixtures
  KINDS = %w[entity blank simple page_record decision].freeze

  module_function

  def with_context(token)
    raise ArgumentError, "Invalid builder fixture token" unless token.match?(/\A[a-f0-9]{32}\z/)

    customer = Customer.find(81721200)
    raise "Pinned platform owner required" unless customer.users.find_by!(email: "lingercoffee@gmail.com").platform_owner?

    Current.with_customer(customer) { yield customer }
  end

  def create(token, kind = "entity")
    raise ArgumentError, "Unknown builder fixture kind" unless KINDS.include?(kind)

    require "factory_bot"
    FactoryBot.definition_file_paths = [Rails.root.join("spec/factories")]
    FactoryBot.reload

    with_context(token) do |customer|
      Entity.transaction do
        entity = FactoryBot.create(:entity, customer: customer, name: entity_name(token),
          property_schema: property_schema_for(kind).to_json)

        flowchart = build_flowchart(customer, entity, token, kind)
        launched = build_launched_flowchart(customer, entity, token, kind)
        [flowchart, launched].each { |record| bind_design_page(customer, entity, record, token) }

        {
          token: token,
          kind: kind,
          entity_id: entity.id,
          entity_name: entity.name,
          flowchart_id: flowchart&.id,
          flowchart_name: flowchart_name(token),
          launched_flowchart_id: launched&.id,
          launched_flowchart_name: launched&.name,
          new_path: "/#{customer.id}/admin/maintenance/flowcharts/new",
          flowchart_edit_path: flowchart && "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}/edit",
          baseline: baseline(customer),
          snapshot: snapshot(token)
        }
      end
    end
  end

  def snapshot(token)
    with_context(token) do |customer|
      entity = Entity.find_by!(customer: customer, name: entity_name(token))
      flowchart = Flowchart.find_by(customer: customer, name: flowchart_name(token))
      {
        entity: { id: entity.id, name: entity.name },
        flowchart: flowchart && {
          id: flowchart.id,
          status: flowchart.status,
          version_id: flowchart.resolved_current_version.id,
          version_count: flowchart.flowchart_versions.count,
          versions: flowchart.flowchart_versions.order(:version_number).map { |version|
            { id: version.id, version_number: version.version_number }
          },
          configuration: flowchart.configuration_json
        }
      }
    end
  end

  def baseline(customer)
    {
      entities: Entity.where(customer: customer, name: %w[BrowserContact employee invoice]).order(:id).map(&:attributes),
      flowcharts: Flowchart.where(customer: customer, name: (1..9).map { |index| "Browser Flow #{index}" }).order(:id).map(&:attributes)
    }
  end

  def cleanup(token)
    with_context(token) do |customer|
      Page.where(customer: customer).where("name LIKE ?", "PwBuilderPage#{token}%").find_each(&:destroy!)
      Flowchart.where(customer: customer, name: [flowchart_name(token), launched_name(token)]).find_each(&:destroy!)
      Entity.where(customer: customer, name: entity_name(token)).find_each(&:destroy!)
      {
        remaining_entities: Entity.where(customer: customer, name: entity_name(token)).count,
        remaining_flowcharts: Flowchart.where(customer: customer, name: [flowchart_name(token), launched_name(token)]).count,
        baseline: baseline(customer)
      }
    end
  end

  def entity_name(token)
    "PwBuilderEntity#{token}"
  end

  def flowchart_name(token)
    "PwBuilderFlow#{token}"
  end

  def launched_name(token)
    "PwBuilderLaunched#{token}"
  end

  def page_name(token, flowchart)
    "PwBuilderPage#{token}-#{flowchart.id}"
  end

  def property_schema_for(kind)
    first_name = { name: "First name", name_slug: "first_name", type: "String", html_type: "text" }
    first_name[:validators] = [{ type: "presence" }] if kind == "page_record"
    [
      first_name,
      { name: "Status", name_slug: "status", type: "String", html_type: "text" },
      { name: "Note", name_slug: "note", type: "String", html_type: "text" }
    ]
  end

  def build_flowchart(customer, entity, token, kind)
    return if kind == "entity"

    if kind == "decision"
      return FactoryBot.create(:flowchart, :draft, customer: customer,
        name: flowchart_name(token), configuration: decision_configuration(token).to_json)
    end

    if kind == "simple"
      configuration = FactoryBot.build(:flowchart, :simple, :draft, customer: customer).configuration_json
      configuration.fetch("elements").find { |node| node.fetch("type") == "end" }["properties"] = {
        "description" => "", "responseType" => "none"
      }
      configuration.fetch("elements").find { |node| node.fetch("id") == "process_1" }["properties"] = {
        "inputs" => [],
        "outputs" => [],
        "steps" => [{
          "id" => "step_seed_#{token[0, 12]}",
          "action" => "log",
          "config" => { "logLevel" => "info", "messageTemplate" => "seed-log", "logger" => "rails" }
        }]
      }
      return FactoryBot.create(:flowchart, :draft, customer: customer,
        name: flowchart_name(token), configuration: configuration.to_json)
    end

    template_key = kind == "blank" ? "blank" : kind
    flowchart = Flowchart.new_with_defaults(
      "name" => flowchart_name(token),
      "template" => template_key,
      "customer_id" => customer.id
    )
    flowchart.save!
    flowchart
  end

  # The editor and test runner take their entity from the pages a flowchart
  # processes, so each seeded flowchart gets a draft page on the entity.
  def bind_design_page(customer, entity, flowchart, token)
    return unless flowchart

    FactoryBot.create(:page, customer: customer, entity: entity, flowchart: flowchart, name: page_name(token, flowchart))
  end

  def build_launched_flowchart(customer, entity, token, kind)
    return unless kind == "blank"

    configuration = FactoryBot.build(:flowchart, :simple, :draft, customer: customer).configuration_json
    configuration.fetch("elements").find { |node| node.fetch("type") == "end" }["properties"] = {
      "description" => "", "responseType" => "none"
    }
    FactoryBot.create(:flowchart, :simple, :launched_status, customer: customer,
      name: launched_name(token), configuration: configuration.to_json)
  end

  # Start → Decision(ctx.params.amount > 100) → High/Low process → End.
  # Each process box has exactly one action. Only Decision (and Loop) may have
  # more than one outgoing connection.
  def decision_configuration(token)
    {
      "elements" => [
        {
          "id" => "start_1", "type" => "start", "x" => 220, "y" => 50, "width" => 100, "height" => 45,
          "label" => "Start", "properties" => { "inputs" => [], "outputs" => [] }
        },
        {
          "id" => "decision_1", "type" => "decision", "x" => 220, "y" => 160, "width" => 100, "height" => 45,
          "label" => "Check amount",
          "properties" => {
            "routeBy" => "condition",
            "condition" => {
              "type" => "group",
              "joins" => [],
              "conditions" => [{
                "kind" => "field",
                "leftOperand" => "ctx.params.amount",
                "operator" => ">",
                "rightOperand" => "100"
              }]
            }
          }
        },
        {
          "id" => "process_high", "type" => "process", "x" => 360, "y" => 280, "width" => 100, "height" => 45,
          "label" => "High value",
          "properties" => {
            "inputs" => [],
            "outputs" => [],
            "steps" => [{
              "id" => "step_high_#{token[0, 12]}",
              "action" => "assign_value",
              "config" => { "resultVar" => "high_value", "valueType" => "string", "stringValue" => "taken" }
            }]
          }
        },
        {
          "id" => "process_low", "type" => "process", "x" => 80, "y" => 280, "width" => 100, "height" => 45,
          "label" => "Low value",
          "properties" => {
            "inputs" => [],
            "outputs" => [],
            "steps" => [{
              "id" => "step_low_#{token[0, 12]}",
              "action" => "assign_value",
              "config" => { "resultVar" => "low_value", "valueType" => "string", "stringValue" => "taken" }
            }]
          }
        },
        {
          "id" => "end_1", "type" => "end", "x" => 220, "y" => 400, "width" => 100, "height" => 45,
          "label" => "End", "properties" => { "description" => "", "responseType" => "none" }
        }
      ],
      "connections" => [
        { "id" => "c1", "from" => "start_1", "to" => "decision_1", "fromPosition" => "bottom", "toPosition" => "top" },
        { "id" => "c2", "from" => "decision_1", "to" => "process_high", "label" => "Yes", "matchValue" => "true",
          "fromPosition" => "right", "toPosition" => "top" },
        { "id" => "c3", "from" => "decision_1", "to" => "process_low", "label" => "No", "matchValue" => "false",
          "fromPosition" => "left", "toPosition" => "top" },
        { "id" => "c4", "from" => "process_high", "to" => "end_1", "fromPosition" => "bottom", "toPosition" => "top" },
        { "id" => "c5", "from" => "process_low", "to" => "end_1", "fromPosition" => "bottom", "toPosition" => "top" }
      ],
      "metadata" => { "canvas" => { "width" => 1200, "height" => 800 }, "created_at" => Time.current.iso8601 }
    }
  end
end
