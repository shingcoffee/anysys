# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::GeneratePage do
  let_it_be(:customer) { create(:customer) }

  def call_for(entity)
    Current.with_customer(customer) do
      described_class.call(entity: entity, customer: customer)
    end
  end

  it "launches an admin-only page from the entity current version" do
    entity = create(:entity, :with_name_status_schema, customer: customer, name: "Student")

    result = nil
    expect { result = call_for(entity) }.to change(Page, :count).by(1)
    expect(result.ok).to eq(true)
    expect(result.page.entity_id).to eq(entity.id)
    expect(result.page.reload).to have_attributes(launched: true, status: "active")
    expect(result.page.visible_audiences).to eq(%w[admin])
    expect(result.page.fields).not_to be_empty
    expect(result.created).to eq("Student")

    again = call_for(entity)
    expect(again.ok).to eq(true)
    expect(again.skipped).to eq(:page_exists)
    expect(again.page).to eq(result.page)
  end

  it "binds the page to the customer's own Save page record once the shared one is deleted" do
    Flowcharts::DefaultPageFlowchart.fetch.update_columns(status: Flowchart.statuses[:deleted])
    entity = create(:entity, :with_name_status_schema, customer: customer, name: "Student")

    result = call_for(entity)

    expect(result.ok).to be(true)
    expect(result.page.reload).to have_attributes(launched: true, flowchart: Flowcharts::DefaultPageFlowchart.for_customer(customer))
    expect(result.page.flowchart.customer_id).to eq(customer.id)
  end

  it "keys the form as the entity's create page so journey generation reuses it" do
    entity = create(:entity, :with_name_status_schema, customer: customer, name: "Student")

    expect(call_for(entity).page.reload.action_key).to eq("student_new")
  end

  it "suffixes the create page key when it is taken" do
    entity = create(:entity, :with_name_status_schema, customer: customer, name: "Student")
    create(:page, customer: customer, action_key: "student_new")

    expect(call_for(entity).page.reload.action_key).to eq("student_new_2")
  end

  [
    [false, %w[admin], "admin-only"],
    [true, %w[admin member], "member"],
    [true, %w[admin member public], "public"]
  ].each do |launched, audiences, label|
    it "reuses a #{launched ? 'launched' : 'offline'} #{label} page without rewriting its settings or version" do
      entity = create(:entity, :with_name_status_schema, customer: customer, name: "Student")
      page = call_for(entity).page
      page.assign_attributes(launched: launched, name: "Customized Student")
      page.visible_audiences = audiences
      page.save!
      original = page.reload.attributes
      configuration = page.configuration_json.deep_dup
      result = nil

      expect { result = call_for(entity) }
        .not_to change { [Page.count, PageVersion.count] }

      expect(result).to have_attributes(ok: true, skipped: :page_exists, created: nil, page: page)
      expect(page.reload.attributes).to eq(original)
      expect(page.configuration_json).to eq(configuration)
    end
  end

  it "rebuilds and launches an inactive generated page without rewriting its audiences" do
    entity = create(:entity, :with_name_status_schema, customer: customer, name: "Student")
    page = call_for(entity).page
    page.launched = false
    page.visible_audiences = %w[admin member public]
    page.save!
    page.soft_delete
    result = nil

    expect { result = call_for(entity) }.not_to change { Page.with_deleted.count }

    expect(result).to have_attributes(ok: true, created: "Student")
    expect(result.page.id).to eq(page.id)
    expect(page.reload).to have_attributes(status: "active", launched: true)
    expect(page.visible_audiences).to eq(%w[admin member public])
  end

  [:en, :"zh-CN"].each do |locale|
    it "rolls back a new page with no launchable fields and returns a #{locale} failure" do
      entity = create(:entity, customer: customer, name: "Empty Student")
      result = nil

      expect { I18n.with_locale(locale) { result = call_for(entity) } }
        .not_to change { [Page.with_deleted.count, PageVersion.count, PageConfigurationContent.count] }

      expect(result).to have_attributes(ok: false, skipped: :launch_failed, page: nil, created: nil)
      expect(result.message).to include(I18n.t("maint_core.errors.page_launch.no_fields", locale: locale))
      expect(result.message).not_to include("Translation missing")
      expect(entity.reload).to be_active
    end
  end

  it "rolls back restoration, settings, and versions when an inactive page rebuild cannot launch" do
    entity = create(:entity, customer: customer, name: "Empty Student")
    built = Current.with_customer(customer) do
      Pages::Activities::CreateFromEntityVersion.call(
        entity: entity, version: entity.current_version, customer: customer
      )
    end
    expect(built).to be_success
    page = built.page
    page.name = "Customized Empty Student"
    page.visible_audiences = %w[admin member public]
    page.save!
    page.soft_delete
    original = page.reload.attributes
    original_configuration = page.configuration_json.deep_dup
    result = nil

    expect { result = call_for(entity) }
      .not_to change { [Page.with_deleted.count, PageVersion.count, PageConfigurationContent.count] }

    expect(result).to have_attributes(ok: false, skipped: :launch_failed, page: nil, created: nil)
    expect(result.message).to include(I18n.t("maint_core.errors.page_launch.no_fields"))
    expect(page.reload.attributes).to eq(original)
    expect(page.configuration_json).to eq(original_configuration)
    expect(page).to be_inactive
  end

  it "does not write another tenant's page" do
    other = create(:customer)
    entity = create(:entity, :with_name_status_schema, customer: customer, name: "Student")
    Current.with_customer(other) { described_class.call(entity: entity, customer: customer) }
    page = Page.find_by(name: "Student")
    expect(page.customer_id).to eq(customer.id)
  end

  it "rejects an entity owned by another tenant" do
    foreign = create(:entity, :with_name_status_schema, customer: create(:customer))
    result = nil

    expect { result = call_for(foreign) }.not_to change { [Page.with_deleted.count, PageVersion.count] }

    expect(result).to have_attributes(ok: false, skipped: :wrong_tenant, page: nil)
  end

  it "rejects a shared entity without creating a tenant page or changing the shared definition" do
    shared = create(:entity, :shared, :with_name_status_schema)
    head = shared.current_version_id
    result = nil

    expect { result = call_for(shared) }.not_to change { [Page.with_deleted.count, PageVersion.count] }

    expect(result).to have_attributes(ok: false, skipped: :wrong_tenant, page: nil)
    expect(shared.reload.current_version_id).to eq(head)
  end

  it "keeps page generation denied by the accepted snapshot after a catalog increase" do
    entity = create(:entity, :with_name_status_schema, customer: customer, name: "Student")
    plan = create(:billing_plan)
    Billing::AssignPlanLimits.call(plan: plan, limits: { "page" => 0, "entity" => 5, "member" => 1 })
    subscription = create(:billing_subscription, customer: customer, plan: plan)
    Billing::AssignPlanLimits.call(plan: plan, limits: { "page" => 10 })

    result = nil
    expect { result = call_for(entity) }.not_to change(Page, :count)
    expect(result).to have_attributes(ok: false, skipped: :quota)
    expect(subscription.reload.plan_snapshot.dig("limits", "page")).to eq(0)
  end
end
