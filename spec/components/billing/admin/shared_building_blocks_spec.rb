# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Billing admin building blocks", type: :component do
  describe Billing::Admin::DetailListComponent do
    it "renders label, hint and value rows" do
      render_inline(described_class.new) do |list|
        list.with_row(label: "Code", mono: true) { "pro-monthly" }
        list.with_row(label: "Collection mode", hint: "Uses the default method") { "Gateway" }
      end
      expect(page).to have_css("dl dt", text: "Code")
      expect(page).to have_css("dl dd.font-mono", text: "pro-monthly")
      expect(page).to have_css("dt", text: "Uses the default method")
      expect(page).to have_css("dd", text: "Gateway")
    end

    it "renders nothing without rows" do
      expect(render_inline(described_class.new).to_html).to be_blank
    end
  end

  describe Billing::Admin::FieldRowComponent do
    it "ties the label to the control and shows the hint" do
      render_inline(described_class.new(label: "Grace period", for_id: "grace", hint: "Days after failure")) do
        '<input id="grace">'.html_safe
      end
      expect(page).to have_css("label[for='grace']", text: "Grace period")
      expect(page).to have_text("Days after failure")
      expect(page).to have_field("grace")
    end

    it "omits the hint when absent" do
      render_inline(described_class.new(label: "Tax rate", for_id: "tax")) { "control" }
      expect(page).not_to have_css("p.text-caption")
    end
  end

  describe Billing::Admin::PlatformPageComponent do
    let(:plans_path) { "/81721200/admin/maintenance/platform/billing/plans" }

    it "links the section crumb and keeps the tab strip on nested pages" do
      with_request_url "#{plans_path}/1/edit" do
        render_inline(described_class.new(customer_id: 81721200, section: :plans, title: "Edit Plan",
                                          crumbs: [{ label: "prod", path: "#{plans_path}/1" }, { label: "Edit" }])) { "Body" }
      end
      crumbs = page.find("nav[aria-label]:not([data-billing-nav])")
      expect(crumbs).to have_link("Maintenance", href: "/81721200/admin/maintenance")
      expect(crumbs).to have_link("Plans", href: plans_path)
      expect(crumbs).to have_link("prod", href: "#{plans_path}/1")
      expect(page).to have_css("nav[data-billing-nav] a[aria-current='page']", text: "Plans")
      expect(page).to have_css("h1", text: "Edit Plan")
      expect(page).to have_text("Body")
    end

    it "leaves the section crumb unlinked on the section index and honours section_path" do
      with_request_url "/81721200/admin/maintenance/platform/billing/invoices" do
        render_inline(described_class.new(customer_id: 81721200, section: :invoices, title: "All Invoices")) { "Body" }
      end
      expect(page.find("nav[aria-label]:not([data-billing-nav])")).not_to have_link("Invoices")

      component = described_class.new(customer_id: 81721200, section: :invoices, title: "INV-1",
                                      crumbs: [{ label: "INV-1" }], section_path: "/filtered")
      with_request_url("/81721200/admin/maintenance/platform/billing/invoices/1") { render_inline(component) { "Body" } }
      expect(page).to have_link("Invoices", href: "/filtered")
    end
  end

  describe Billing::Admin::EmptyStateComponent do
    it "renders icon, title, description and optional action" do
      render_inline(described_class.new(icon: :tag, title: "No coupons yet", description: "Create one")) do |empty|
        empty.with_action { "New coupon" }
      end
      expect(page).to have_css("svg[aria-hidden='true']", visible: :all)
      expect(page).to have_text("No coupons yet")
      expect(page).to have_text("Create one")
      expect(page).to have_text("New coupon")
    end

    it "renders without description or action" do
      render_inline(described_class.new(icon: :document, title: "No invoices"))
      expect(page).to have_text("No invoices")
      expect(page).not_to have_css("div.pt-1")
    end
  end
end
