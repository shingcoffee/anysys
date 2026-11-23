# frozen_string_literal: true

require "rails_helper"

RSpec.describe LandingHeaderComponent, type: :component do
  let(:customer) { build_stubbed(:customer, name: "Acme") }
  let(:user) { build_stubbed(:user, customer: customer, first_name: "Jane", last_name: "Doe") }

  it "greets the user by first name and shows customer name, date, and subtitle" do
    rendered = render_inline(described_class.new(customer: customer, user: user))
    expect(rendered.css("h1").text).to include("Welcome back, Jane")
    expect(rendered.text).to include("Acme")
    expect(rendered.text).to include(I18n.l(Date.current, format: :long))
    expect(rendered.css("time[datetime='#{Date.current.iso8601}']")).to be_present
    expect(rendered.text).to include(I18n.t("admin_misc.dashboard.subtitle"))
  end

  it "renders block content as the header actions" do
    rendered = render_inline(described_class.new(customer: customer, user: user)) { "<a href='/x'>Go</a>".html_safe }
    expect(rendered.css("header a[href='/x']").text).to eq("Go")
  end

  it "omits the actions wrapper without block content" do
    rendered = render_inline(described_class.new(customer: customer, user: user))
    expect(rendered.css("header > div").size).to eq(1)
  end
end
