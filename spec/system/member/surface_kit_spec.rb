# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member surface kit smoke", type: :system do
  def page
    Capybara.current_session
  end

  let(:customer) { create(:customer) }
  let(:user)     { create(:user, :member, customer: customer) }

  let(:stub_surface) do
    Member::Surface.new(
      key: :smoke_widgets, label: "Smoke widgets", icon: :sparkles,
      enabled_for: ->(_u) { true },
      index: Member::Surface::Index.new(
        title: "Smoke widgets",
        subtitle: "All formats",
        scope: ->(u) { Payments::Payment.where(user_id: u.id, customer_id: u.customer_id).order(:id) },
        columns: [
          { key: :date,     label: "Date",         value: ->(r) { r.created_at }, format: :date },
          { key: :provider, label: "Provider",     value: ->(r) { r.provider.titleize } },
          { key: :amount,   label: "Amount",       value: ->(r) { r.amount }, format: :money_major, align: :right },
          { key: :status,   label: "Status",       value: ->(r) { r.status }, format: :status_pill },
          { key: :otn,      label: "Out trade no", value: ->(r) { r.out_trade_no }, format: :mono }
        ],
        empty_state: { headline: "Nothing here", body: "yet", icon: :sparkles },
        per_page: 20
      ),
      detail: Member::Surface::Detail.new(
        title:    ->(r) { "Smoke #{r.out_trade_no}" },
        subtitle: ->(r) { "At #{I18n.l(r.created_at, format: :long)}" },
        meta:     ->(r) { { label: r.status, tone: :success } },
        sections: [
          { key: :primary, rows: [
              { key: :amount,   label: "Amount",   value: ->(r) { r.amount }, format: :money_major_large },
              { key: :status,   label: "Status",   value: ->(r) { r.status }, format: :status_pill },
              { key: :provider, label: "Provider", value: ->(r) { r.provider.titleize } }
          ]},
          { key:   :mono,
            title: "Mono",
            list:  ->(r) { [{ left: "id", right: r.out_trade_no, format: :mono }] } }
        ]
      )
    )
  end

  let(:source_class) do
    surface = stub_surface
    Class.new(Member::SurfaceSource) do
      define_singleton_method(:key)      { :smoke_widgets_src }
      define_singleton_method(:name)     { "Smoke"             }
      define_singleton_method(:position) { 99                  }
      define_method(:surfaces) { [surface] }
    end
  end

  before do
    enable_module!("authentication", customer, name: "Authentication")

    @prior_sources = Member::Surfaces::SourceRegistry.all
    Member::Surfaces::SourceRegistry.register(source_class)

    order = create(:payment_order, customer: customer, external_ref: "T",
                    subject: "S", amount: 42.00, currency: "CNY", status: "pending")
    create(:payment, customer: customer, user: user, payment_order: order,
           provider: "alipay", flow: "qr", out_trade_no: "OUT123",
           amount: 42.00, status: "succeeded")
    sign_in user
  end

  after do
    Member::Surfaces::SourceRegistry.reset!
    @prior_sources.each { |s| Member::Surfaces::SourceRegistry.register(s) }
  end

  it "renders the index, then a detail page, exercising every advertised format" do
    visit "/#{customer.id}/member/smoke_widgets"

    expect(page).to have_text("Smoke widgets")
    expect(page).to have_text("Alipay")
    expect(page).to have_text("$42.00")
    expect(page).to have_css("span.badge.badge-success", text: I18n.t("common.status.succeeded"))
    expect(page).to have_css("span.font-mono", text: "OUT123")

    click_link "View", match: :first

    expect(page).to have_css("h1", text: "Smoke OUT123")
    expect(page).to have_css("span.text-3xl.font-mono", text: "$42.00")
    expect(page).to have_css("span.badge.badge-success", text: I18n.t("common.status.succeeded"))
    expect(page).to have_link("Back to Smoke widgets")
  end
end
