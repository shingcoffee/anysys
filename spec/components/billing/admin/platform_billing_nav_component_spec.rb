# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::PlatformBillingNavComponent, type: :component do
  let(:customer_id) { "81721200" }

  # Stub all route helpers called by the component.
  before do
    stub_helpers = double(
      "helpers",
      admin_maintenance_platform_billing_plans_path:           "/81721200/admin/maintenance/platform/billing/plans",
      admin_maintenance_platform_billing_countable_items_path: "/81721200/admin/maintenance/platform/billing/countable_items",
      admin_maintenance_platform_billing_coupons_path:         "/81721200/admin/maintenance/platform/billing/coupons",
      admin_maintenance_platform_billing_subscriptions_path:   "/81721200/admin/maintenance/platform/billing/subscriptions",
      admin_maintenance_platform_billing_invoices_path:        "/81721200/admin/maintenance/platform/billing/invoices",
      admin_maintenance_platform_billing_settings_path:        "/81721200/admin/maintenance/platform/billing/settings"
    )
    allow_any_instance_of(described_class).to receive(:helpers).and_return(stub_helpers)
  end

  def build_component(current_path:)
    described_class.new(customer_id: customer_id, current_path: current_path)
  end

  describe "default rendering (no active tab)" do
    before do
      render_inline(build_component(current_path: "/81721200/admin/maintenance/platform/billing/plans"))
    end

    it "renders a nav element with aria-label" do
      expect(page).to have_css("nav[aria-label='Billing sections']")
    end

    it "renders all tab labels" do
      %w[Plans Coupons Subscriptions Invoices Settings].each do |label|
        expect(page).to have_link(label)
      end
      expect(page).to have_link("Countable Items")
    end

    it "renders links pointing to the correct paths" do
      expect(page).to have_link("Plans", href: "/81721200/admin/maintenance/platform/billing/plans")
      expect(page).to have_link("Countable Items", href: "/81721200/admin/maintenance/platform/billing/countable_items")
    end
  end

  describe "active tab detection" do
    it "marks Plans tab active when current_path includes /billing/plans" do
      render_inline(build_component(current_path: "/81721200/admin/maintenance/platform/billing/plans"))
      active_link = page.find("a[aria-current='page']")
      expect(active_link.text.strip).to eq("Plans")
    end

    it "marks Countable Items tab active when current_path includes /billing/countable_items" do
      render_inline(build_component(current_path: "/81721200/admin/maintenance/platform/billing/countable_items"))
      active_link = page.find("a[aria-current='page']")
      expect(active_link.text.strip).to eq("Countable Items")
    end

    it "marks Coupons tab active when current_path includes /billing/coupons" do
      render_inline(build_component(current_path: "/81721200/admin/maintenance/platform/billing/coupons"))
      active_link = page.find("a[aria-current='page']")
      expect(active_link.text.strip).to eq("Coupons")
    end

    it "marks Subscriptions tab active when current_path includes /billing/subscriptions" do
      render_inline(build_component(current_path: "/81721200/admin/maintenance/platform/billing/subscriptions"))
      active_link = page.find("a[aria-current='page']")
      expect(active_link.text.strip).to eq("Subscriptions")
    end

    it "marks Invoices tab active when current_path includes /billing/invoices" do
      render_inline(build_component(current_path: "/81721200/admin/maintenance/platform/billing/invoices"))
      active_link = page.find("a[aria-current='page']")
      expect(active_link.text.strip).to eq("Invoices")
    end

    it "marks Settings tab active when current_path includes /billing/settings" do
      render_inline(build_component(current_path: "/81721200/admin/maintenance/platform/billing/settings"))
      active_link = page.find("a[aria-current='page']")
      expect(active_link.text.strip).to eq("Settings")
    end

    it "does not set aria-current on inactive tabs" do
      render_inline(build_component(current_path: "/81721200/admin/maintenance/platform/billing/plans"))
      # Only one aria-current="page" should be present
      expect(page).to have_css("a[aria-current='page']", count: 1)
    end
  end

  describe "#active_tab?" do
    it "returns true when path includes the segment after /billing/" do
      component = build_component(current_path: "/81721200/admin/maintenance/platform/billing/coupons/new")
      expect(component.send(:active_tab?, "coupons")).to be true
    end

    it "returns false when path does not include the segment" do
      component = build_component(current_path: "/81721200/admin/maintenance/platform/billing/plans")
      expect(component.send(:active_tab?, "coupons")).to be false
    end
  end
end
