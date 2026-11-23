# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::Home do
  def reset_module_catalog!(active_optional: [])
    # A schema-loaded verification DB need not contain the boot catalog. These
    # examples explicitly establish the mandatory and optional modules they use.
    [FeatureModules::Authentication::Registration, FeatureModules::Email::Registration,
     FeatureModules::Payment::Registration, FeatureModules::Sms::Registration].each(&:register!)
    FeatureModules::Module.find_each do |fm|
      attrs = if fm.key == "authentication"
        { status: :active, required: true }
      elsif active_optional.include?(fm.key)
        { status: :active, required: false }
      else
        { required: false, status: :inactive }
      end
      fm.update!(attrs)
    end
  end

  def hrefs_of(result)
    values = []
    values.concat(result.metrics.map(&:href))
    result.modules.each do |card|
      values << card.primary&.href
      values.concat(card.secondaries.map(&:href))
    end
    values.concat(result.setup_items.map(&:href))
    values.concat(result.recent_pages.map(&:href))
    values.concat(result.recent_entities.map(&:href))
    values.concat(result.actions.map(&:path))
    values.compact
  end

  describe ".call metrics" do
    let(:customer) { create(:customer) }

    before { reset_module_catalog!(active_optional: []) }

    it "returns four metrics matching LandingStats" do
      create(:entity, customer: customer, name: "Metric Entity")
      entity = Entity.find_by!(customer_id: customer.id, name: "Metric Entity")
      create(:page, customer: customer, entity: entity, launched: true)
      create(:page, customer: customer, entity: entity, launched: false)
      create(:user, customer: customer)

      result = described_class.call(customer: customer)
      stats = LandingStats.for(customer).to_h
      cid = customer.id

      expect(result.metrics.map(&:key)).to eq(%w[entities pages modules users])
      entities, pages, modules, users = result.metrics

      expect(entities).to have_attributes(
        label: I18n.t("admin_misc.dashboard.stats.entities"),
        value: stats[:entities],
        sub_label: nil,
        href: "/#{cid}/admin/domains",
        icon: described_class::METRIC_ICONS.fetch("entities")
      )
      expect(pages).to have_attributes(
        label: I18n.t("admin_misc.dashboard.stats.pages"),
        value: stats[:pages][:total],
        sub_label: I18n.t("admin_misc.dashboard.pages_sub_label", count: stats[:pages][:launched]),
        href: "/#{cid}/admin/domains",
        icon: described_class::METRIC_ICONS.fetch("pages")
      )
      expect(modules).to have_attributes(
        label: I18n.t("admin_misc.dashboard.stats.modules"),
        value: stats[:modules_enabled],
        sub_label: nil,
        href: "/#{cid}/admin/maintenance/modules",
        icon: described_class::METRIC_ICONS.fetch("modules")
      )
      expect(users).to have_attributes(
        label: I18n.t("admin_misc.dashboard.stats.users"),
        value: stats[:users],
        sub_label: nil,
        href: "/#{cid}/admin/modules/authentication/users",
        icon: described_class::METRIC_ICONS.fetch("users")
      )
    end
  end

  describe "auth-only customer" do
    let(:customer) { create(:customer) }

    before { reset_module_catalog!(active_optional: %w[email]) }

    it "returns only the authentication card, an enable_module action, and incomplete module setup" do
      result = described_class.call(customer: customer)

      expect(result.modules.map(&:key)).to eq(%w[authentication])
      expect(result.actions.map(&:key)).to include("enable_module")
      setup = result.setup_items.find { |item| item.key == "enable_module" }
      expect(setup.done).to eq(false)
      expect(setup.href).to eq("/#{customer.id}/admin/maintenance/modules")
    end
  end

  describe "email and payment enabled" do
    let(:customer) { create(:customer) }

    before do
      reset_module_catalog!(active_optional: %w[email payment])
      enable_module!("email", customer)
      enable_module!("payment", customer)
    end

    it "returns those cards with catalog hrefs and never a checkout URL" do
      result = described_class.call(customer: customer)
      cid = customer.id
      email = result.modules.find { |card| card.key == "email" }
      payment = result.modules.find { |card| card.key == "payment" }

      expect(email.primary.href).to eq("/#{cid}/admin/modules/emails/templates")
      expect(payment.primary.href).to eq("/#{cid}/admin/modules/payments/transactions")
      expect(hrefs_of(result).grep(/checkout|module_settings|flowchart/i)).to eq([])
    end
  end

  describe "setup items" do
    let(:customer) { create(:customer) }

    before { reset_module_catalog!(active_optional: %w[email]) }

    it "returns all four items and treats optional-module enablement as the module step" do
      result = described_class.call(customer: customer)
      expect(result.setup_items.map(&:key)).to eq(%w[create_entity launch_page enable_module invite_user])
      expect(result.setup_items.map(&:done)).to eq([false, false, false, false])
      expect(result.setup_items.map(&:href)).to eq([
        "/#{customer.id}/admin/assistant",
        "/#{customer.id}/admin/domains",
        "/#{customer.id}/admin/maintenance/modules",
        "/#{customer.id}/admin/modules/authentication/users/new"
      ])
      expect(result.setup_items.map(&:label)).to eq([
        I18n.t("admin_misc.dashboard.setup.items.create_entity"),
        I18n.t("admin_misc.dashboard.setup.items.launch_page"),
        I18n.t("admin_misc.dashboard.setup.items.enable_module"),
        I18n.t("admin_misc.dashboard.setup.items.invite_user")
      ])

      entity = create(:entity, customer: customer)
      create(:page, customer: customer, entity: entity, launched: true)
      enable_module!("email", customer)
      create(:user, customer: customer)

      done = described_class.call(customer: customer)
      expect(done.setup_items.map(&:done)).to eq([true, true, true, true])
    end
  end

  describe "recents" do
    let(:customer) { create(:customer) }
    let(:other) { create(:customer) }

    before { reset_module_catalog!(active_optional: []) }

    it "includes own and shared pages, excludes other tenants, and caps at 5" do
      entity = create(:entity, customer: customer, name: "Home Entity")
      other_entity = create(:entity, customer: other, name: "Other Entity")
      shared_entity = create(:entity, :shared, name: "Shared Home Entity")

      own_pages = Array.new(6) do |i|
        create(:page, customer: customer, entity: entity, name: "Own Page #{i}", launched: i.even?)
      end
      other_page = create(:page, customer: other, entity: other_entity, name: "Other Page")
      shared_page = create(:page, :shared, entity: shared_entity, name: "Shared Home Page", launched: true)

      own_pages.each_with_index { |page, i| page.update_column(:updated_at, (i + 1).minutes.ago) }
      other_page.update_column(:updated_at, Time.current)
      shared_page.update_column(:updated_at, 30.seconds.ago)
      own_pages[5].update_column(:updated_at, 1.year.ago)

      result = Current.set(customer: other) { described_class.call(customer: customer) }

      expect(result.recent_pages.size).to eq(5)
      names = result.recent_pages.map(&:name)
      expect(names).to include("Shared Home Page")
      expect(names).not_to include("Other Page")
      expect(names).not_to include("Own Page 5")
      live = result.recent_pages.find { |item| item.name == "Own Page 0" }
      draft = result.recent_pages.find { |item| item.name == "Own Page 1" }
      expect(live.badge).to eq("live")
      expect(live.href).to eq("/#{customer.id}/admin/pages/#{own_pages[0].id}")
      expect(draft.badge).to eq("draft")
      expect(live.updated_at).to be_within(1.second).of(own_pages[0].reload.updated_at)
    end

    it "includes own and shared entities, excludes other tenants and bridges, and caps at 5" do
      own = Array.new(6) { |i| create(:entity, customer: customer, name: "Own Ent #{i}", display_label: "Label #{i}") }
      other_entity = create(:entity, customer: other, name: "Other Ent")
      shared = create(:entity, :shared, name: "Shared Ent", display_label: "Shared Label")
      create(:entity, customer: customer, name: "Bridge Ent", category: :bridge)

      own.each_with_index { |entity, i| entity.update_column(:updated_at, (i + 1).minutes.ago) }
      other_entity.update_column(:updated_at, Time.current)
      shared.update_column(:updated_at, 30.seconds.ago)
      own[5].update_column(:updated_at, 1.year.ago)

      result = Current.set(customer: other) { described_class.call(customer: customer) }

      expect(result.recent_entities.size).to eq(5)
      names = result.recent_entities.map(&:name)
      expect(names).to include("Shared Label")
      expect(names).to include("Label 0")
      expect(names).not_to include("Other Ent")
      expect(names).not_to include("Bridge Ent")
      expect(names).not_to include("Label 5")
      expect(result.recent_entities.map(&:badge).uniq).to eq([nil])
      labeled = result.recent_entities.find { |item| item.name == "Label 0" }
      expect(labeled.href).to eq("/#{customer.id}/admin/entities/#{own[0].id}")
      expect(labeled.updated_at).to be_within(1.second).of(own[0].reload.updated_at)
    end
  end

  describe "actions" do
    let(:customer) { create(:customer) }

    it "omits enable_module when every optional module is assigned and caps at 8" do
      reset_module_catalog!(active_optional: %w[email payment sms])
      %w[email payment sms].each { |key| enable_module!(key, customer) }

      result = described_class.call(customer: customer)
      keys = result.actions.map(&:key)

      expect(keys).to eq(%w[
        create_entity
        new_page
        invite_user
        module_email
        module_payment
        module_sms
        module_email_secondary
        module_sms_secondary
      ])
      expect(keys).not_to include("enable_module")
      expect(result.actions.size).to eq(8)

      email = result.modules.find { |card| card.key == "email" }
      sms = result.modules.find { |card| card.key == "sms" }
      expect(result.actions.find { |action| action.key == "module_email" }).to have_attributes(
        label: email.primary.label,
        path: email.primary.href,
        icon: Admin::Maintenance::Platform::ModuleSettingsHelper::MODULE_ICON_PATHS.fetch("email")
      )
      expect(result.actions.find { |action| action.key == "module_sms_secondary" }.path)
        .to eq(sms.secondaries.first.href)
      expect(hrefs_of(result).grep(/checkout|module_settings|flowchart/i)).to eq([])
    end

    it "includes enable_module when an optional module is still unassigned" do
      reset_module_catalog!(active_optional: %w[email])
      FeatureModules::CustomerAssignment.where(customer: customer).delete_all

      result = described_class.call(customer: customer)
      action = result.actions.find { |item| item.key == "enable_module" }
      expect(action).to have_attributes(
        label: I18n.t("admin_misc.dashboard.actions.enable_module.label"),
        description: I18n.t("admin_misc.dashboard.actions.enable_module.description"),
        path: "/#{customer.id}/admin/maintenance/modules",
        icon: described_class::ACTION_ICONS.fetch("enable_module")
      )
    end

    it "always leads with create_entity, new_page, and invite_user" do
      reset_module_catalog!(active_optional: [])
      result = described_class.call(customer: customer)
      expect(result.actions.first(3).map(&:key)).to eq(%w[create_entity new_page invite_user])
      expect(result.actions.first(3).map(&:path)).to eq([
        "/#{customer.id}/admin/assistant",
        "/#{customer.id}/admin/maintenance/pages/new",
        "/#{customer.id}/admin/modules/authentication/users/new"
      ])
    end
  end

  describe "cross-tenant isolation" do
    it "never surfaces customer B pages, entities, or module assignments for customer A" do
      reset_module_catalog!(active_optional: %w[email payment])
      customer_a = create(:customer)
      customer_b = create(:customer)
      enable_module!("email", customer_a)
      enable_module!("payment", customer_b)

      entity_b = create(:entity, customer: customer_b, name: "B Entity")
      create(:page, customer: customer_b, entity: entity_b, name: "B Page")

      result = described_class.call(customer: customer_a)
      expect(result.modules.map(&:key)).to include("email")
      expect(result.modules.map(&:key)).not_to include("payment")
      expect(result.recent_pages.map(&:name)).not_to include("B Page")
      expect(result.recent_entities.map(&:name)).not_to include("B Entity")
    end
  end

  describe "locales" do
    it "translates module blurbs in zh-CN" do
      reset_module_catalog!(active_optional: %w[email])
      customer = create(:customer)
      enable_module!("email", customer)

      I18n.with_locale(:"zh-CN") do
        card = described_class.call(customer: customer).modules.find { |item| item.key == "email" }
        expect(card.description).to eq("模板、受众名单与发送记录。")
      end
    end
  end
end
