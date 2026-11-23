# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::PlanCatalogComponent, type: :component do
  let(:active_plan) do
    instance_double(
      Billing::Plan,
      free?:            false,
      id:               1,
      code:             "pro-monthly",
      name:             "Pro Monthly",
      interval:         "monthly",
      amount_usd: 99.00,
      amount_cny: 99.00,
      trial_days:       14,
      active?:          true,
      is_default?:      false
    )
  end

  let(:default_plan) do
    instance_double(
      Billing::Plan,
      free?:            false,
      id:               2,
      code:             "starter",
      name:             "Starter",
      interval:         "yearly",
      amount_usd: 499.00,
      amount_cny: 499.00,
      trial_days:       0,
      active?:          true,
      is_default?:      true
    )
  end

  let(:inactive_plan) do
    instance_double(
      Billing::Plan,
      free?:            false,
      id:               3,
      code:             "legacy",
      name:             "Legacy",
      interval:         "monthly",
      amount_usd: 20.00,
      amount_cny: 20.00,
      trial_days:       0,
      active?:          false,
      is_default?:      false
    )
  end

  let(:free_plan) do
    instance_double(
      Billing::Plan,
      free?:            true,
      id:               4,
      code:             "free",
      name:             "Free",
      interval:         "monthly",
      amount_usd: 0.00,
      amount_cny: 0.00,
      trial_days:       0,
      active?:          true,
      is_default?:      false
    )
  end

  before do
    stub_helpers = double(
      "helpers",
      admin_maintenance_platform_billing_plan_path:      "/81721200/admin/maintenance/platform/billing/plans/1",
      edit_admin_maintenance_platform_billing_plan_path: "/81721200/admin/maintenance/platform/billing/plans/1/edit",
      new_admin_maintenance_platform_billing_plan_path:  "/81721200/admin/maintenance/platform/billing/plans/new",
      protect_against_forgery?: false
    )
    allow_any_instance_of(described_class).to receive(:helpers).and_return(stub_helpers)
  end

  def build_component(plans, customer_id: "81721200", **opts)
    described_class.new(plans: plans, customer_id: customer_id, **opts)
  end

  def render_catalog(plans, **opts)
    render_inline(build_component(plans, **opts))
  end

  describe "zero state" do
    before { render_catalog([]) }

    it "shows empty state message and a link to create the first plan" do
      aggregate_failures do
        expect(page).to have_text("No plans yet.")
        expect(page).to have_text("Your billing catalog is empty.")
        expect(page).to have_link("Create the first plan.")
        expect(page).to have_css("svg[aria-hidden='true']", visible: :all)
      end
    end
  end

  describe "with plans" do
    before { render_catalog([active_plan, default_plan, inactive_plan]) }

    it "renders one card per plan in a list" do
      expect(page).to have_css("ul[role='list'] > li", count: 3)
    end

    it "renders plan codes in monospace" do
      expect(page).to have_css(".font-mono", text: "pro-monthly")
      expect(page).to have_css(".font-mono", text: "starter")
      expect(page).to have_css(".font-mono", text: "legacy")
    end

    it "renders plan names" do
      expect(page).to have_text("Pro Monthly")
      expect(page).to have_text("Starter")
      expect(page).to have_text("Legacy")
    end

    it "renders the interval" do
      expect(page).to have_text("Monthly")
      expect(page).to have_text("Yearly")
    end

    it "renders formatted CNY price" do
      expect(page).to have_text("¥99.00 CNY")
      expect(page).to have_text("¥499.00 CNY")
      expect(page).to have_text("¥20.00 CNY")
    end

    it "renders formatted USD price with interval suffix" do
      expect(page).to have_text("$99.00")
      expect(page).to have_text("$499.00")
      expect(page).to have_text("/mo")
      expect(page).to have_text("/yr")
    end

    it "renders trial info when present" do
      expect(page).to have_text("14-day trial")
    end

    it "renders Active status for active plans" do
      expect(page).to have_text("Active", count: 2)
    end

    it "renders Inactive status for inactive plans" do
      expect(page).to have_text("Inactive")
    end

    it "renders Default badge for the default plan only" do
      expect(page).to have_text("Default", count: 1)
    end

    it "renders View and Edit links for each plan" do
      expect(page).to have_link("View", count: 3)
      expect(page).to have_link("Edit", count: 3)
    end

    it "renders an accessible Archive button per plan" do
      expect(page).to have_button("Archive Pro Monthly")
      expect(page).to have_button("Archive Starter")
      expect(page).to have_button("Archive Legacy")
    end

    it "uses ghost and secondary card actions instead of a primary button" do
      expect(page).to have_css("a.btn-ghost", text: "View", count: 3)
      expect(page).to have_css("a.btn-secondary", text: "Edit", count: 3)
      expect(page).not_to have_css("a.btn-primary")
    end

    it "mutes inactive plan cards" do
      expect(page).to have_css("li.opacity-60", text: "Legacy")
    end
  end

  describe "free plans" do
    it "renders 'Free' instead of a zero price" do
      render_catalog([free_plan])
      expect(page).to have_text("Free")
    end
  end

  describe "limits" do
    let(:plan) { Billing::Plan.create!(code: "pro", name: "Pro", amount_usd: 29.00, amount_cny: 199.00, interval: "monthly") }
    let(:entity_item) { Billing::CountableItem.create!(key: "entity", label: "Entities", enabled: true) }
    let(:item_page) { Billing::CountableItem.create!(key: "page", label: "Pages", enabled: true) }

    before { Billing::PlanLimit.create!(billing_plan_id: plan.id, item_key: "entity", limit_value: 3) }

    it "renders an enforced limit and unlimited capacity when no limit row exists" do
      render_catalog([plan], items: [entity_item, item_page], customer_id: "81721200")
      expect(page.find("dt", text: "Entities", exact_text: true).find(:xpath, "..").find("dd").text.strip).to eq("3")
      expect(page.find("dt", text: "Pages", exact_text: true).find(:xpath, "..").find("dd").text.strip).to eq("Unlimited")
    end

    it "still displays explicitly unlimited purchased catalog capacity" do
      Billing::PlanLimit.create!(billing_plan_id: plan.id, item_key: "page", limit_value: Billing::PlanLimit::UNLIMITED)
      render_catalog([plan], items: [item_page])
      expect(page.find("dt", text: "Pages", exact_text: true).find(:xpath, "..").find("dd").text.strip).to eq("Unlimited")
    end
  end

  describe "#format_amount" do
    subject(:component) { build_component([]) }

    it "formats amounts with correct currency symbols (CNY, USD, EUR) and defaults to CNY" do
      aggregate_failures do
        expect(component.format_amount(99.00, "CNY")).to eq("¥99.00")
        expect(component.format_amount(99.00, "USD")).to eq("$99.00")
        expect(component.format_amount(99.00, "EUR")).to eq("€99.00")
        expect(component.format_amount(99.00)).to eq("¥99.00")
      end
    end
  end

  it "renders supplied 25-row pagination without changing the owner's route or locale" do
    render_catalog([active_plan], pagination: { page: 2, per_page: 25, total: 51, total_pages: 3 },
      page_path: ->(page) { "/81721200/admin/maintenance/platform/billing/plans?page=#{page}&locale=zh-CN" })
    expect(page).to have_link(href: "/81721200/admin/maintenance/platform/billing/plans?page=1&locale=zh-CN")
    expect(page).to have_link(href: "/81721200/admin/maintenance/platform/billing/plans?page=3&locale=zh-CN")
    expect(page).to have_css("ul[role='list'] > li", count: 1)
  end
end
