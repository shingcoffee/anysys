# frozen_string_literal: true

require "rails_helper"

RSpec.describe "platform billing routes", type: :routing do
  let(:prefix) { "/81721200/admin/maintenance/platform/billing" }

  %w[plans coupons subscriptions invoices].each do |resource|
    it "keeps #{resource} oversight in the owner namespace" do
      expect(get: "#{prefix}/#{resource}").to route_to(
        controller: "admin/maintenance/platform/billing/#{resource}", action: "index", customer_id: "81721200"
      )
    end
  end

  %w[mark_paid void retry].each do |action|
    it "keeps #{action} a POST action" do
      expect(post: "#{prefix}/invoices/7/#{action}").to route_to(
        controller: "admin/maintenance/platform/billing/invoices", action: action, customer_id: "81721200", id: "7"
      )
      expect(get: "#{prefix}/invoices/7/#{action}").not_to be_routable
    end
  end

  %w[plans coupons].each do |resource|
    it "keeps the #{resource} removal route for domain archival" do
      expect(delete: "#{prefix}/#{resource}/7").to route_to(
        controller: "admin/maintenance/platform/billing/#{resource}", action: "destroy", customer_id: "81721200", id: "7"
      )
    end
  end
end
