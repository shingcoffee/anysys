# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityIndexSettings::Operation::Update do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:entity) { create(:entity, :with_name_status_schema, customer: customer) }

  def call_update(keys)
    described_class.call(
      customer: customer,
      entity: entity,
      params: ActionController::Parameters.new(visible_column_keys: keys)
    )
  end

  it "persists selected attribute slugs for the customer/entity" do
    result = call_update(%w[name status])
    expect(result.success?).to be(true)

    setting = EntityIndexSetting.find_by!(customer_id: customer.id, entity_id: entity.id)
    expect(setting.visible_column_keys).to eq(%i[name status])
  end

  it "allows an empty array (hide attribute columns)" do
    result = call_update([])
    expect(result.success?).to be(true)

    setting = EntityIndexSetting.find_by!(customer_id: customer.id, entity_id: entity.id)
    expect(setting.visible_column_keys).to eq([])
  end

  it "treats a lone blank hidden-field value as an empty selection" do
    result = call_update([""])
    expect(result.success?).to be(true)

    setting = EntityIndexSetting.find_by!(customer_id: customer.id, entity_id: entity.id)
    expect(setting.visible_column_keys).to eq([])
  end

  it "rejects unknown slugs" do
    result = call_update(%w[name not_a_field])
    expect(result.success?).to be(false)
    expect(result.errors[:base]).to include(
      I18n.t("admin_misc.entities.index_setting.errors.invalid_keys")
    )
    expect(EntityIndexSetting.where(customer_id: customer.id, entity_id: entity.id)).to be_empty
  end

  it "rejects more than MAX_VISIBLE_KEYS entries" do
    keys = Array.new(EntityIndexSettings::Contract::Update::MAX_VISIBLE_KEYS + 1) { |i| "k#{i}" }
    result = call_update(keys)
    expect(result.success?).to be(false)
    expect(result.errors[:base]).to include(
      I18n.t("admin_misc.entities.index_setting.errors.too_many")
    )
  end

  it "scopes the overlay to the given customer_id" do
    other = create(:customer)
    result = described_class.call(
      customer: other,
      entity: entity,
      params: { visible_column_keys: %w[name] }
    )
    expect(result.success?).to be(true)
    expect(EntityIndexSetting.find_by!(customer_id: other.id, entity_id: entity.id).visible_column_keys)
      .to eq(%i[name])
    expect(EntityIndexSetting.find_by(customer_id: customer.id, entity_id: entity.id)).to be_nil
  end

  it "accepts a calculated slug and saves it" do
    calculated_entity = create(:entity, customer: customer, name: "Calculated Columns")
    calculated_entity.property_schema_json = [
      { "name" => "Name", "name_slug" => "name", "type" => "String" },
      { "name" => "Total", "name_slug" => "total", "type" => "Calculated" }
    ]
    calculated_entity.save!

    result = described_class.call(
      customer: customer,
      entity: calculated_entity,
      params: ActionController::Parameters.new(visible_column_keys: %w[total])
    )
    expect(result.success?).to be(true)
    setting = EntityIndexSetting.find_by!(customer_id: customer.id, entity_id: calculated_entity.id)
    expect(setting.visible_column_keys).to eq(%i[total])
  end

  it "rejects system column slugs even if present on the schema" do
    entity.property_schema_json = [
      { "name" => "Name", "name_slug" => "name", "type" => "String" },
      { "name" => "Id", "name_slug" => "id", "type" => "String" }
    ]
    entity.save!

    result = call_update(%w[id])
    expect(result.success?).to be(false)
    expect(result.errors[:base]).to include(
      I18n.t("admin_misc.entities.index_setting.errors.invalid_keys")
    )
  end

  it "accepts a computed slug as a visible_column_keys value" do
    computed_entity = create(:entity, customer: customer, name: "Computed Columns")
    computed_entity.property_schema_json = [
      { "name" => "Name", "name_slug" => "name", "type" => "String" },
      { "name" => "Average Score", "name_slug" => "average_score", "type" => "Computed" }
    ]
    computed_entity.save(validate: false)

    result = described_class.call(
      customer: customer,
      entity: computed_entity,
      params: ActionController::Parameters.new(visible_column_keys: %w[average_score])
    )
    expect(result.success?).to be(true)
    setting = EntityIndexSetting.find_by!(customer_id: customer.id, entity_id: computed_entity.id)
    expect(setting.visible_column_keys).to eq(%i[average_score])
  end
end
