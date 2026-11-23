# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccessPoints::PageClassProvider do
  subject(:provider) { described_class.new }

  it "yields a single 'all pages' descriptor" do
    results = provider.call(customer_id: 12_345_678)
    expect(results.size).to eq(1)
    expect(results.first.subject_type).to eq("PageClass")
    expect(results.first.subject_key).to eq("Page")
    expect(results.first.actions).to contain_exactly(:read, :create, :update, :destroy)
    expect(results.first.label).to eq("All pages")
    expect(results.first.description).to eq("Grant covers every Page record for this customer.")
  end

  it "translates the all-pages copy in zh-CN" do
    d = I18n.with_locale(:"zh-CN") { provider.call(customer_id: 12_345_678).first }
    expect(d.label).to eq(I18n.t("admin_settings.access_points.pages_all", locale: :"zh-CN"))
  end
end
