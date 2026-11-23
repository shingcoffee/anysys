# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::Purge do
  let(:customer) { create(:customer) }
  let(:other) { create(:customer) }

  def override_as(tenant, record, attribute, value)
    Current.with_customer(tenant) do
      loaded = record.class.find(record.id)
      loaded.public_send("#{attribute}=", value)
      loaded.save!
    end
  end

  it "purges owned and hidden rows plus shared overrides without deleting shared parents or another tenant" do
    owned = create(:entity, customer: customer)
    hidden = create(:entity, customer: customer, status: :inactive)
    shared_entity = create(:entity, :shared)
    shared_page = create(:page, :shared, entity: shared_entity)
    shared_flowchart = create(:flowchart, :empty, :shared_type)
    shared_constant = create(:constant, :shared)
    owned_page = create(:page, customer: customer, entity: owned, status: :inactive)
    owned_flowchart = create(:flowchart, :empty, customer: customer, status: :deleted)
    create(:constant, customer: customer)
    shared_entry = create(:entity_entry, customer: customer, entity: shared_entity)
    hidden_entry = create(:entity_entry, customer: customer, entity: hidden)
    log = create(:feature_module_log, customer: customer, entity_entry: hidden_entry)
    EntityIndexSetting.create!(customer: customer, entity: shared_entity, config: "{}")
    foreign_entry = create(:entity_entry, customer: other, entity: shared_entity)
    override_as(customer, shared_entity, :description, "purged override")
    override_as(other, shared_entity, :description, "retained override")
    override_as(customer, shared_page, :configuration, JSON.parse(shared_page.configuration).merge("audit" => "override").to_json)
    override_as(customer, shared_flowchart, :configuration, JSON.parse(shared_flowchart.configuration).merge("audit" => "override").to_json)
    ConstantCustomerOverride.create!(constant: shared_constant, customer_id: customer.id, options: ["purge"])
    ConstantCustomerOverride.create!(constant: shared_constant, customer_id: other.id, options: ["keep"])
    default_head = shared_entity.current_version_id
    content_ids = EntityDefinitionContent.where(customer_id: customer.id).ids
    customer.soft_delete

    report = described_class.dependencies(customers: Customer.only_deleted.where(id: customer.id))
    expect(report[:counts]["entities"]).to eq(2)
    expect(report[:counts]["feature_module_logs"]).to eq(1)
    expect(report[:counts]["entity_customer_heads"]).to eq(1)
    expect(report[:blockers]).to be_empty
    expect(Entity.with_deleted.exists?(hidden.id)).to be(true)

    result = described_class.call(customers: Customer.only_deleted.where(id: customer.id))
    expect(result).to be_success
    expect(result.deleted_count).to eq(1)
    expect(Customer.unscoped.exists?(customer.id)).to be(false)
    expect(Entity.unscoped.where(id: [owned.id, hidden.id])).to be_empty
    expect(Page.unscoped.exists?(owned_page.id)).to be(false)
    expect(Flowchart.unscoped.exists?(owned_flowchart.id)).to be(false)
    expect(EntityEntry.where(id: [shared_entry.id, hidden_entry.id])).to be_empty
    expect(FeatureModules::Log.exists?(log.id)).to be(false)
    [EntityCustomerHead, PageCustomerHead, FlowchartCustomerHead, ConstantCustomerOverride, EntityIndexSetting,
     EntityVersion, PageVersion, FlowchartVersion, FeatureModules::CustomerAssignment].each do |model|
      expect(model.unscoped.where(customer_id: customer.id)).to be_empty
    end
    expect(EntityDefinitionContent.where(id: content_ids)).to be_empty
    expect(PageConfigurationContent.where(customer_id: customer.id)).to be_empty
    expect(FlowchartConfigurationContent.where(customer_id: customer.id)).to be_empty
    expect(shared_entity.reload.current_version_id).to eq(default_head)
    expect(Page.exists?(shared_page.id)).to be(true)
    expect(Flowchart.exists?(shared_flowchart.id)).to be(true)
    expect(Constant.exists?(shared_constant.id)).to be(true)
    expect(EntityEntry.exists?(foreign_entry.id)).to be(true)
    expect(EntityCustomerHead.exists?(entity_id: shared_entity.id, customer_id: other.id)).to be(true)
    expect(ConstantCustomerOverride.exists?(constant: shared_constant, customer_id: other.id)).to be(true)
  end

  it "rolls back all selected customers, dependent rows, pointers and content on a late delete failure" do
    tenants = [customer, other]
    entities = tenants.map { |tenant| create(:entity, customer: tenant, status: :inactive) }
    tenants.each(&:soft_delete)
    heads = entities.map(&:current_version_id)
    content_ids = entities.map { |entity| entity.current_version.content_id }
    allow_any_instance_of(ActiveRecord::Relation).to receive(:delete_all).and_wrap_original do |original|
      raise ActiveRecord::InvalidForeignKey if original.receiver.klass.table_name == "customers"

      original.call
    end

    result = described_class.call(customers: tenants)
    expect(result.success?).to be(false)
    expect(result.deleted_count).to eq(0)
    expect(Customer.unscoped.where(id: tenants.map(&:id)).count).to eq(2)
    expect(entities.map { |entity| entity.reload.current_version_id }).to eq(heads)
    expect(EntityDefinitionContent.where(id: content_ids).count).to eq(content_ids.uniq.size)
  end

  it "preserves content still referenced by an unselected tenant" do
    owned = create(:entity, customer: customer)
    content = owned.current_version.content
    survivor = create(:entity, customer: other)
    version = survivor.entity_versions.create!(customer_id: other.id, version_number: 2, content: content)
    customer.soft_delete

    expect(described_class.call(customers: [customer])).to be_success
    expect(EntityDefinitionContent.exists?(content.id)).to be(true)
    expect(version.reload.payload).to eq(content.payload)
  end

  it "refuses to purge the platform customer" do
    platform = ensure_platform_customer(name: "Platform Owner")
    result = described_class.call(customers: [platform])

    expect(result.success?).to be(false)
    expect(result.error_code).to eq(:platform_customer)
    expect(Customer.unscoped.find(platform.id).status).to eq("active")
  end

  it "reports an external tenant dependency and refuses to partially purge" do
    owned = create(:entity, customer: customer)
    # Legacy/corrupt cross-tenant foreign keys must never cause foreign data to
    # be swept into a tenant's deletion plan.
    foreign = create(:entity_entry, customer: other, entity: owned)
    customer.soft_delete
    result = described_class.call(customers: [customer])

    expect(result.success?).to be(false)
    expect(result.error_code).to eq(:foreign_dependency)
    expect(result.dependencies[:blockers]).to include(include(table: "entity_entries", ids: [foreign.id]))
    expect(Customer.unscoped.exists?(customer.id)).to be(true)
    expect(Entity.exists?(owned.id)).to be(true)
    expect(EntityEntry.exists?(foreign.id)).to be(true)
  end

  it "also cleans hidden dependents when Customer#destroy! is called directly" do
    hidden = create(:entity, customer: customer, status: :inactive)
    hidden_entry = create(:entity_entry, customer: customer, entity: hidden)
    create(:feature_module_log, customer: customer, entity_entry: hidden_entry)
    customer.entities.load
    customer.users.load
    customer.destroy!

    expect(Entity.unscoped.exists?(hidden.id)).to be(false)
    expect(EntityEntry.exists?(hidden_entry.id)).to be(false)
    expect(FeatureModules::Log.where(customer_id: customer.id)).to be_empty
  end
end
