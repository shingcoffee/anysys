# frozen_string_literal: true

require "rails_helper"
require_relative "../audience_domain_helpers"

RSpec.describe Sms::Contacts::SyncEntity do
  include SmsAudienceDomainHelpers
  let(:customer) { create(:customer) }
  let(:actor) { create(:user, :admin, customer: customer) }
  let(:schema) do
    [{ "name" => "Mobile", "name_slug" => "mobile", "html_type" => "tel" },
     { "name" => "Name", "name_slug" => "full_name", "html_type" => "text" },
     { "name" => "City", "name_slug" => "city", "html_type" => "text" },
     { "name" => "VIP", "name_slug" => "vip", "html_type" => "checkbox" },
     { "name" => "Telephone label only", "name_slug" => "phone_label", "html_type" => "text" }]
  end
  let(:source) { create(:entity, customer: customer, property_schema: schema.to_json) }
  let(:mapping) do
    { entity_id: source.id, phone_field: "mobile", name_field: "full_name", country_code: "CN",
      timezone: "Asia/Shanghai", attribute_map: { "city" => "city", "vip" => "vip" }, after_entry_id: 0 }
  end

  def entry(data = {}, source: self.source, customer: self.customer, **fields)
    create(:entity_entry, entity: source, customer: customer,
      data: { "mobile" => "+8613800138000", "full_name" => "Alice", "city" => "Beijing", "vip" => true }.merge(data).merge(fields).to_json)
  end

  def sync(attributes = {}, preview: false, actor: self.actor, **fields)
    described_class.call(customer: customer, actor: actor, attributes: mapping.merge(attributes).merge(fields), preview: preview)
  end

  it "previews exact outcomes without writing contacts, consent, messages, quota or jobs" do
    item = entry
    clear_enqueued_jobs
    result = sync(preview: true)
    expect(result).to be_success
    expect(result.value).to include(preview: true, scanned: 1, created: 1, updated: 0, unchanged: 0,
      invalid: 0, conflicts: 0, next_after_entry_id: item.id, through_entry_id: item.id, has_more: false)
    expect(result.value[:items]).to eq([{ entry_id: item.id, contact_id: nil, outcome: :created, error_code: nil }])
    expect([Sms::Contact.count, Sms::ConsentEvent.count, Sms::Message.count, Sms::CampaignRecipient.count, Sms::OptOut.count]).to eq([0, 0, 0, 0, 0])
    expect(enqueued_jobs).to be_empty
  end

  it "creates unknown contacts with only the frozen source mapping keys and idempotent replay" do
    entry
    result = sync
    contact = Sms::Contact.sole
    expect(result.value[:created]).to eq(1)
    expect(contact).to have_attributes(consent_status: "unknown", source_kind: "entity", source_entity_id: source.id)
    expect(contact.custom_attributes).to eq("city" => "Beijing", "vip" => true)
    expect(contact.source_mapping.keys.sort).to eq(%w[attribute_map country_code name_field phone_field timezone])
    expect(sync.value).to include(created: 0, updated: 0, unchanged: 1)
    expect(Sms::Contact.count).to eq(1)
    expect(Sms::ConsentEvent.count).to eq(0)
  end

  it "attaches an unlinked same-phone contact without granting or overwriting unmapped attributes" do
    contact = create(:sms_contact, :granted, customer: customer, phone_e164: "+8613800138000",
      custom_attributes: { "untouched" => "keep", "city" => "Old" })
    entry
    expect(sync.value[:updated]).to eq(1)
    expect(contact.reload).to have_attributes(consent_status: "granted", source_entity_id: source.id)
    expect(contact.custom_attributes).to include("untouched" => "keep", "city" => "Beijing")
  end

  it "resets consent only when a linked source's phone changes and never restores archives" do
    row = entry
    sync
    contact = Sms::Contact.sole
    consent(contact)
    contact.reload.update!(status: "archived")
    expect(sync.value[:unchanged]).to eq(1)
    expect(contact.reload.consent_status).to eq("granted")
    row.update!(data: row.data_json.merge("mobile" => "+8613900139000").to_json)
    expect(sync.value[:updated]).to eq(1)
    expect(contact.reload).to have_attributes(status: "archived", consent_status: "unknown", consent_changed_at: nil)
    expect(contact.consent_events.count).to eq(1)
  end

  it "reports source and phone identity conflicts without merging or changing existing records" do
    row = entry
    other_source = create(:entity, customer: customer, property_schema: schema.to_json)
    other_entry = entry(source: other_source)
    contact = create(:sms_contact, customer: customer, phone_e164: "+8613800138000", source_kind: "entity",
      source_entity: other_source, source_entry: other_entry)
    expect(sync.value).to include(conflicts: 1, created: 0, updated: 0)
    expect(contact.reload.source_entry_id).to eq(other_entry.id)
    contact.update!(phone_e164: "+8613900139000")
    sync
    linked = Sms::Contact.find_by!(source_entry_id: row.id)
    row.update!(data: row.data_json.merge("mobile" => contact.phone_e164).to_json)
    expect(sync.value[:items].first[:error_code]).to eq(:identity_conflict)
    expect(linked.reload.phone_e164).to eq("+8613800138000")
  end

  it "continues a valid batch across missing phones, invalid scalar data and conflicts" do
    first = entry("mobile" => nil)
    second = entry("mobile" => "+8613900139000", "city" => ["bad"])
    third = entry("mobile" => "+8613700137000")
    result = sync
    expect(result.value).to include(scanned: 3, invalid: 2, created: 1)
    expect(result.value[:items].map { |item| item[:entry_id] }).to eq([first.id, second.id, third.id])
    expect(Sms::Contact.sole.phone_e164).to eq("+8613700137000")
  end

  it "fails the whole malformed mapping before any writes and never infers a telephone field from its label" do
    entry
    [{ phone_field: "phone_label" }, { phone_field: "mobile; SQL" }, { attribute_map: { "consent_status" => "missing" } },
      { attribute_map: [] }, { name_field: "__send__" }, { country_code: "ZZ" }, { timezone: "No/Zone" },
      { after_entry_id: "1x" }, { after_entry_id: 5, through_entry_id: 2 }, { source_kind: "manual" }].each do |bad|
      expect(sync(bad)).not_to be_success
    end
    expect(Sms::Contact.count).to eq(0)
  end

  it "requires admin authorization and accessible ordinary sources, including for owner cross-tenant browsing" do
    foreign = create(:entity, property_schema: schema.to_json)
    expect(sync(entity_id: foreign.id).code).to eq(:not_found)
    expect(sync(actor: create(:user, :member, customer: customer)).code).to eq(:forbidden)
    owner = find_or_create_platform_owner
    expect(sync({ entity_id: foreign.id }, actor: owner).code).to eq(:not_found)
    source.update!(status: :inactive)
    expect(sync.code).to eq(:not_found)
  end

  it "excludes bridges and native model extensions from the source catalog" do
    source
    bridge = create(:entity, customer: customer)
    Entity.unscoped.where(id: bridge.id).update_all(category: Entity.categories.fetch("bridge"))
    extension = create(:entity, customer: customer)
    Entity.unscoped.where(id: extension.id).update_all(category: Entity.categories.fetch("extension"), extended_model: "Authentication::User")
    catalog = Sms::EntitySources.new(customer: customer)
    expect(catalog.entities).to eq([{ id: source.id, label: source.display_label }])
    expect { catalog.find(bridge.id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { catalog.find(extension.id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(catalog.fields(nil)).to eq(phone: [], scalar: [])
  end

  it "uses explicit tenant overrides of shared definitions even with a different ambient tenant/platform mode" do
    shared = create(:entity, :shared, property_schema: schema.to_json)
    replacement = schema.map { |field| field["name_slug"] == "mobile" ? field.merge("name_slug" => "tenant_mobile") : field }
    Current.set(customer: customer, shared_resources_mode: false) do
      shared.property_schema_json = replacement
      shared.commit_version!
    end
    own_entry = create(:entity_entry, entity: shared, customer: customer, data: { "tenant_mobile" => "+8613800138000" }.to_json)
    Current.set(customer: nil, shared_resources_mode: false) do
      create(:entity_entry, entity: shared.reload, customer: create(:customer), data: { "mobile" => "+8613900139000" }.to_json)
    end
    Current.set(customer: create(:customer), shared_resources_mode: true) do
      result = sync(entity_id: shared.id, phone_field: "tenant_mobile", name_field: nil, attribute_map: {})
      expect(result).to be_success
      expect(result.value[:scanned]).to eq(1)
      expect(Sms::Contact.sole.source_entry_id).to eq(own_entry.id)
      expect(Current.shared_resources_mode).to be(true)
    end
  end

  it "revalidates a changed schema on every explicit continuation" do
    entry
    result = sync(preview: true)
    Current.with_customer(customer) do
      source.property_schema_json = schema.reject { |field| field["name_slug"] == "mobile" }
      source.commit_version!
    end
    expect(sync(through_entry_id: result.value[:through_entry_id]).errors).to have_key(:phone_field)
    expect(Sms::Contact.count).to eq(0)
  end

  it "accepts the Entity schema's digit-leading slugs without treating them as contact attribute keys" do
    schema = [{ "name" => "2024 mobile", "name_slug" => "2024_mobile", "html_type" => "tel" }]
    source = create(:entity, customer: customer, property_schema: schema.to_json)
    create(:entity_entry, entity: source, customer: customer, data: { "2024_mobile" => "+8613800138000" }.to_json)
    result = sync(entity_id: source.id, phone_field: "2024_mobile", name_field: nil, attribute_map: {})
    expect(result.value[:created]).to eq(1)
    expect(Sms::Contact.sole.phone_e164).to eq("+8613800138000")
  end

  it "freezes a tenant-only high-water mark and handles exactly 100 rows per explicit batch" do
    rows = 102.times.map { |index| entry("mobile" => "+86139#{format('%08d', index)}") }
    preview = sync(preview: true).value
    expect(preview).to include(scanned: 100, through_entry_id: rows.last.id, next_after_entry_id: rows[99].id, has_more: true)
    entry("mobile" => "+8613700137000")
    first = sync(through_entry_id: preview[:through_entry_id]).value
    second = sync(after_entry_id: first[:next_after_entry_id], through_entry_id: first[:through_entry_id]).value
    expect(first[:scanned]).to eq(100)
    expect(second).to include(scanned: 2, created: 2, has_more: false, next_after_entry_id: rows.last.id)
    expect(Sms::Contact.count).to eq(102)
    expect(Sms::ConsentEvent.count).to eq(0)
  end

  it "predicts within-batch duplicate-phone conflicts consistently with execution" do
    entry
    entry
    preview = sync(preview: true).value
    executed = sync.value
    expect(preview).to include(created: 1, conflicts: 1)
    expect(executed).to include(created: 1, conflicts: 1)
    expect(preview[:items].map { |item| item[:outcome] }).to eq(executed[:items].map { |item| item[:outcome] })
  end

  it "rolls back a database unique race for one item and continues the next item" do
    entry
    entry("mobile" => "+8613900139000")
    connection = Sms::Contact.connection
    connection.execute(<<~SQL)
      CREATE TEMP TRIGGER sms_sync_unique_race BEFORE INSERT ON sms_contacts
      WHEN NEW.phone_e164 = '+8613800138000'
      BEGIN
        SELECT RAISE(ABORT, 'UNIQUE constraint failed: sms_contacts.customer_id, sms_contacts.phone_e164');
      END
    SQL
    expect(sync.value).to include(conflicts: 1, created: 1, scanned: 2)
    expect(Sms::Contact.sole.phone_e164).to eq("+8613900139000")
  ensure
    connection&.execute("DROP TRIGGER IF EXISTS sms_sync_unique_race")
  end

  it "reports empty batches without deleting missing source contacts" do
    row = entry
    sync
    contact = Sms::Contact.sole
    row.destroy!
    result = sync.value
    expect(result).to include(scanned: 0, through_entry_id: 0, next_after_entry_id: nil, has_more: false)
    expect(contact.reload.source_entry_id).to be_nil
    expect(contact.status).to eq("active")
  end
end
