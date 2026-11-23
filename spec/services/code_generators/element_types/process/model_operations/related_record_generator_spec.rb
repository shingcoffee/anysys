# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::RelatedRecordGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  def generate(config = described_class.sample_input)
    described_class.new({ "config" => config }, context).generate_body
  end

  def errors(config)
    described_class.new({ "config" => config }, context).validate_config(config)
  end

  def run_body(config, ctx)
    body = generate(config)
    runner = Class.new do
      class_eval <<~RUBY, __FILE__, __LINE__ + 1
        def run(ctx)
          #{body}
        end
      RUBY
    end
    runner.new.run(ctx)
  end

  it "has only :required errors for schema defaults" do
    defaults = described_class._config_schema.defaults
    unexpected = errors(defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"related_record.failed",
          FlowchartRuntime::JoinResolver::Error
        ) do
          related = FlowchartRuntime::JoinResolver.related(
            ctx,
            association: "Course",
            operation: "find",
            source: ctx[:model]
          )
          ctx[:related_record] = related
          return false if related == false
          return FlowchartRuntime::Step.fail(ctx, :"related_record.not_found") unless related
          true
        end
      end
    RUBY
  end

  it "emits a BodyLint-clean body for each operation" do
    %w[find create update list count].each do |operation|
      config = described_class.sample_input.merge("operation" => operation)
      next if errors(config).any?

      code = generate(config)
      expect(code).to include("FlowchartRuntime::JoinResolver.related(ctx")
      expect(code).to include("operation: #{operation.inspect}")
      expect(CodeGenerators::BodyLint.check(code, outputs: %w[related_record]).ok?).to be(true), code
    end
  end

  it "omits not_found when find onNotFound is nil and emits it when fail" do
    keep = generate(described_class.sample_input.merge("operation" => "find", "onNotFound" => "fail"))
    expect(keep).to include("related_record.not_found")
    quiet = generate(described_class.sample_input.merge("operation" => "find", "onNotFound" => "nil"))
    expect(quiet).not_to include("related_record.not_found")
  end

  describe "behaviour" do
    let(:customer) { create(:customer) }
    let(:other) { create(:customer) }

    def link_entities(source:, target:, customer:)
      attrs = {
        name: "assoc_#{source.name.parameterize(separator: '_')}_#{target.name.parameterize(separator: '_')}",
        category: :bridge,
        property_schema: [
          { "name" => source.name, "name_slug" => source.name.parameterize(separator: "_"),
            "type" => Entity::ENTITY_REFERENCE_TYPE, "html_type" => "number", "entity_id" => source.id.to_s },
          { "name" => target.name, "name_slug" => target.name.parameterize(separator: "_"),
            "type" => Entity::ENTITY_REFERENCE_TYPE, "html_type" => "number", "entity_id" => target.id.to_s }
        ].to_json
      }
      bridge = if customer
        create(:entity, attrs.merge(customer: customer))
      else
        create(:entity, :shared, attrs)
      end
      source.associations_json = [{ "target_entity_id" => target.id, "bridge_entity_id" => bridge.id }]
      source.save(validate: false)
      [Entity.find(source.id), Entity.find(target.id), Entity.find(bridge.id)]
    end

    def entry(entity:, customer:, data:)
      create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: data)
    end

    def bridge_row(bridge:, customer:, source:, target:, source_entity:, target_entity:)
      create(:entity_entry, :with_data, entity: bridge, customer: customer, entry_data: {
        source_entity.name.parameterize(separator: "_") => source.id.to_s,
        target_entity.name.parameterize(separator: "_") => target.id.to_s
      })
    end

    it "finds the tenant related row and ignores the other tenant" do
      source = create(:entity, name: "Student", customer: customer, property_schema: [{ "name_slug" => "name", "type" => "String" }].to_json)
      target = create(:entity, name: "Course", customer: customer, property_schema: [{ "name_slug" => "title", "type" => "String" }].to_json)
      source, target, bridge = link_entities(source: source, target: target, customer: customer)

      own_source = entry(entity: source, customer: customer, data: { "name" => "Ada" })
      own_target = entry(entity: target, customer: customer, data: { "title" => "Math" })
      foreign_source = entry(entity: source, customer: other, data: { "name" => "Ada" })
      foreign_target = entry(entity: target, customer: other, data: { "title" => "Math" })
      bridge_row(bridge: bridge, customer: customer, source: own_source, target: own_target, source_entity: source, target_entity: target)
      bridge_row(bridge: bridge, customer: other, source: foreign_source, target: foreign_target, source_entity: source, target_entity: target)

      model = FlowchartRuntime::Entries.find_by({ bound_entity: source, customer_id: customer.id }, "id" => own_source.id)
      ctx = { bound_entity: source, customer_id: customer.id, model: model, errors: [] }
      config = { "association" => target.id, "operation" => "find", "modelVariable" => "model" }

      expect(run_body(config, ctx)).to be(true)
      expect(ctx[:related_record].id).to eq(own_target.id)

      miss = ctx.merge(model: FlowchartRuntime::Entries.find_by({ bound_entity: source, customer_id: customer.id }, "id" => own_source.id), errors: [])
      miss[:model] = entry(entity: source, customer: customer, data: { "name" => "NoLink" })
      expect(run_body(config, miss)).to be(false)
      expect(miss[:errors]).to eq([I18n.t("flowchart_runtime.errors.related_record.not_found")])
    end

    it "checks assignment keys against the association's target, named or by id, only from the page's record" do
      source = create(:entity, name: "Student", customer: customer, property_schema: [{ "name_slug" => "name", "type" => "String" }].to_json)
      target = create(:entity, name: "Course", customer: customer, property_schema: [{ "name_slug" => "title", "type" => "String" }].to_json)
      source, target, = link_entities(source: source, target: target, customer: customer)
      codes = lambda do |config|
        described_class.new({ "config" => config }, { bound_entity: source }).validate_config(config).map(&:code)
      end
      create_with = ->(key, **rest) { { "operation" => "create", "assignments" => [{ "key" => key, "value" => '"x"' }] }.merge(rest) }

      expect(codes.call(create_with.call("title", "association" => "Course"))).to eq([])
      expect(codes.call(create_with.call("title", "association" => target.id.to_s))).to eq([])
      expect(codes.call(create_with.call("name", "association" => "Course"))).to include(:unknown_attribute)
      expect(codes.call(create_with.call("name", "association" => "Course", "modelVariable" => "student"))).to eq([])
    end

    it "creates the target and bridge for the run's customer only" do
      source = create(:entity, name: "Student", customer: customer, property_schema: [{ "name_slug" => "name", "type" => "String" }].to_json)
      target = create(:entity, name: "Course", customer: customer, property_schema: [{ "name_slug" => "title", "type" => "String" }].to_json)
      source, target, bridge = link_entities(source: source, target: target, customer: customer)
      own_source = entry(entity: source, customer: customer, data: { "name" => "Ada" })
      model = FlowchartRuntime::Entries.find_by({ bound_entity: source, customer_id: customer.id }, "id" => own_source.id)
      ctx = { bound_entity: source, customer_id: customer.id, model: model, errors: [] }
      config = {
        "association" => target.id,
        "operation" => "create",
        "assignments" => [{ "key" => "title", "value" => '"Physics"' }]
      }

      expect(run_body(config, ctx)).to be(true)
      created = ctx[:related_record]
      expect(created.customer_id).to eq(customer.id)
      expect(created.title).to eq("Physics")
      expect(EntityEntry.where(entity_id: target.id, customer_id: other.id)).to be_empty
      expect(EntityEntry.where(entity_id: bridge.id, customer_id: customer.id).count).to eq(1)
      expect(EntityEntry.where(entity_id: bridge.id, customer_id: other.id)).to be_empty
    end

    it "updates the tenant related row and keeps a shared entity's rows per customer" do
      source = create(:entity, :shared, name: "Student", property_schema: [{ "name_slug" => "name", "type" => "String" }].to_json)
      target = create(:entity, :shared, name: "Course", property_schema: [{ "name_slug" => "title", "type" => "String" }].to_json)
      source, target, _bridge = link_entities(source: source, target: target, customer: nil)
      own_source = entry(entity: source, customer: customer, data: { "name" => "Ada" })
      own_target = entry(entity: target, customer: customer, data: { "title" => "Math" })
      other_source = entry(entity: source, customer: other, data: { "name" => "Ada" })
      other_target = entry(entity: target, customer: other, data: { "title" => "Math" })
      bridge = Entity.find(source.associations_list.first["bridge_entity_id"])
      bridge_row(bridge: bridge, customer: customer, source: own_source, target: own_target, source_entity: source, target_entity: target)
      bridge_row(bridge: bridge, customer: other, source: other_source, target: other_target, source_entity: source, target_entity: target)

      model = FlowchartRuntime::Entries.find_by({ bound_entity: source, customer_id: customer.id }, "id" => own_source.id)
      ctx = { bound_entity: source, customer_id: customer.id, model: model, errors: [] }
      config = {
        "association" => target.id,
        "operation" => "update",
        "assignments" => [{ "key" => "title", "value" => '"Updated"' }]
      }

      expect(run_body(config, ctx)).to be(true)
      expect(own_target.reload.data_json["title"]).to eq("Updated")
      expect(other_target.reload.data_json["title"]).to eq("Math")
    end

    it "lists and counts tenant related rows and ignores the other tenant" do
      source = create(:entity, name: "Student", customer: customer, property_schema: [{ "name_slug" => "name", "type" => "String" }].to_json)
      target = create(:entity, name: "Course", customer: customer, property_schema: [{ "name_slug" => "title", "type" => "String" }].to_json)
      source, target, bridge = link_entities(source: source, target: target, customer: customer)

      own_source = entry(entity: source, customer: customer, data: { "name" => "Ada" })
      math = entry(entity: target, customer: customer, data: { "title" => "Math" })
      physics = entry(entity: target, customer: customer, data: { "title" => "Physics" })
      foreign_source = entry(entity: source, customer: other, data: { "name" => "Ada" })
      foreign_target = entry(entity: target, customer: other, data: { "title" => "Math" })
      bridge_row(bridge: bridge, customer: customer, source: own_source, target: math, source_entity: source, target_entity: target)
      bridge_row(bridge: bridge, customer: customer, source: own_source, target: physics, source_entity: source, target_entity: target)
      bridge_row(bridge: bridge, customer: other, source: foreign_source, target: foreign_target, source_entity: source, target_entity: target)

      model = FlowchartRuntime::Entries.find_by({ bound_entity: source, customer_id: customer.id }, "id" => own_source.id)
      ctx = { bound_entity: source, customer_id: customer.id, model: model, errors: [] }
      listed = run_body({ "association" => target.id, "operation" => "list", "limit" => 1, "orderBy" => "title", "orderDirection" => "asc" }, ctx)
      expect(listed).to be(true)
      expect(ctx[:related_record].map(&:id)).to eq([math.id])

      counted = ctx.merge(errors: [])
      expect(run_body({ "association" => target.id, "operation" => "count" }, counted)).to be(true)
      expect(counted[:related_record]).to eq(2)
    end

    it "emits order for find and honors onNotFound nil on update" do
      source = generate(described_class.sample_input.merge("operation" => "find", "orderBy" => "title", "orderDirection" => "desc"))
      expect(source).to include('order_by: "title"')
      expect(source).to include('order_direction: "desc"')
      expect(source).to include("related_record.not_found")

      quiet = generate(described_class.sample_input.merge("operation" => "update", "onNotFound" => "nil"))
      expect(quiet).not_to include("related_record.not_found")
    end

    it "returns nil without failing when find onNotFound is nil" do
      source = create(:entity, name: "Student", customer: customer, property_schema: [{ "name_slug" => "name", "type" => "String" }].to_json)
      target = create(:entity, name: "Course", customer: customer, property_schema: [{ "name_slug" => "title", "type" => "String" }].to_json)
      source, target, _bridge = link_entities(source: source, target: target, customer: customer)
      own_source = entry(entity: source, customer: customer, data: { "name" => "Ada" })
      model = FlowchartRuntime::Entries.find_by({ bound_entity: source, customer_id: customer.id }, "id" => own_source.id)
      ctx = { bound_entity: source, customer_id: customer.id, model: model, errors: [] }
      config = { "association" => target.id, "operation" => "find", "onNotFound" => "nil" }

      expect(run_body(config, ctx)).to be(true)
      expect(ctx[:related_record]).to be_nil
      expect(ctx[:errors]).to eq([])
    end

    it "returns nil without failing when update onNotFound is nil" do
      source = create(:entity, name: "Student", customer: customer, property_schema: [{ "name_slug" => "name", "type" => "String" }].to_json)
      target = create(:entity, name: "Course", customer: customer, property_schema: [{ "name_slug" => "title", "type" => "String" }].to_json)
      source, target, _bridge = link_entities(source: source, target: target, customer: customer)
      own_source = entry(entity: source, customer: customer, data: { "name" => "Ada" })
      model = FlowchartRuntime::Entries.find_by({ bound_entity: source, customer_id: customer.id }, "id" => own_source.id)
      ctx = { bound_entity: source, customer_id: customer.id, model: model, errors: [] }
      config = {
        "association" => target.id,
        "operation" => "update",
        "onNotFound" => "nil",
        "assignments" => [{ "key" => "title", "value" => '"Updated"' }]
      }

      expect(run_body(config, ctx)).to be(true)
      expect(ctx[:related_record]).to be_nil
      expect(ctx[:errors]).to eq([])
    end
  end
end
