# frozen_string_literal: true

# Use the checked E2E runner and normal model/version callbacks. Every invocation
# owns exact UUID-named records; the bootstrap's mention/runtime fixtures are read
# only, including during cleanup.
module DragBrowserFixtures
  module_function

  def with_context(token)
    raise ArgumentError, "Invalid drag fixture token" unless token.match?(/\A[a-f0-9]{32}\z/)

    customer = Customer.find(81721200)
    raise "Pinned platform owner required" unless customer.users.find_by!(email: "lingercoffee@gmail.com").platform_owner?

    Current.with_customer(customer) { yield customer }
  end

  def create(token, kind, end_response = "none")
    raise ArgumentError, "Unknown drag fixture kind" unless %w[entity flowchart].include?(kind)
    raise ArgumentError, "Unknown End response fixture" unless %w[none value].include?(end_response)

    require "factory_bot"
    FactoryBot.definition_file_paths = [Rails.root.join("spec/factories")]
    FactoryBot.reload

    with_context(token) do |customer|
      Entity.transaction do
        entity = FactoryBot.create(:entity, customer: customer, name: "PwDragEntity#{token}", property_schema: [
          { name: "First name", name_slug: "first_name", type: "String", html_type: "text" },
          { name: "Status", name_slug: "status", type: "String", html_type: "text" },
          { name: "Note", name_slug: "note", type: "String", html_type: "text" }
        ].to_json)
        flowchart = if kind == "flowchart"
          configuration = FactoryBot.build(:flowchart, :simple, :draft, customer: customer).configuration_json
          # Current rendered End nodes use responseType, rather than an empty
          # properties object from the older :simple factory.
          configuration.fetch("elements").find { |node| node.fetch("type") == "end" }["properties"] = {
            "description" => "", "responseType" => end_response
          }.merge(end_response == "value" ? { "returnValue" => "ctx.result" } : {})
          FactoryBot.create(:flowchart, :draft, customer: customer,
            name: "PwDragFlow#{token}", configuration: configuration.to_json).tap do |record|
            # The editor lists the attributes of the entity its pages bind.
            FactoryBot.create(:page, customer: customer, entity: entity, flowchart: record, name: "PwDragPage#{token}")
          end
        end

        { token: token, entity_id: entity.id, flowchart_id: flowchart&.id,
          entity_edit_path: "/#{customer.id}/admin/maintenance/entities/#{entity.id}/edit",
          flowchart_edit_path: flowchart && "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}/edit",
          baseline: baseline(customer), snapshot: snapshot(token) }
      end
    end
  end

  def snapshot(token)
    with_context(token) do |customer|
      entity = Entity.find_by!(customer: customer, name: "PwDragEntity#{token}")
      flowchart = Flowchart.find_by(customer: customer, name: "PwDragFlow#{token}")
      { entity: { id: entity.id, version_id: entity.resolved_current_version.id,
                  slugs: entity.property_schema_json.map { |attribute| attribute.fetch("name_slug") } },
        flowchart: flowchart && { id: flowchart.id, status: flowchart.status,
                                 version_id: flowchart.resolved_current_version.id,
                                 configuration: flowchart.configuration_json } }
    end
  end

  def baseline(customer)
    { entities: Entity.where(customer: customer, name: %w[BrowserContact employee invoice]).order(:id).map(&:attributes),
      flowcharts: Flowchart.where(customer: customer, name: (1..9).map { |index| "Browser Flow #{index}" }).order(:id).map(&:attributes) }
  end

  def cleanup(token)
    with_context(token) do |customer|
      Page.where(customer: customer, name: "PwDragPage#{token}").find_each(&:destroy!)
      Flowchart.where(customer: customer, name: "PwDragFlow#{token}").find_each(&:destroy!)
      Entity.where(customer: customer, name: "PwDragEntity#{token}").find_each(&:destroy!)
      { remaining_entities: Entity.where(customer: customer, name: "PwDragEntity#{token}").count,
        remaining_flowcharts: Flowchart.where(customer: customer, name: "PwDragFlow#{token}").count,
        baseline: baseline(customer) }
    end
  end
end
