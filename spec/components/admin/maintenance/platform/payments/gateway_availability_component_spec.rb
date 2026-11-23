# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::Payments::GatewayAvailabilityComponent, type: :component do
  def render_gateways(pairs)
    with_request_url("/81721200/admin/maintenance/platform/module_settings/payment/gateways") do
      render_inline(described_class.new(gateways: pairs, customer_id: 81_721_200))
    end
  end

  it "renders a SettingRow and toggle per gateway" do
    gateway = Struct.new(:key, :display_name, :supported_flows).new("stripe", "Stripe", %i[qr h5])
    platform_gateway = instance_double(Payments::PlatformGateway, available?: true)

    render_gateways([[gateway, platform_gateway]])

    expect(page).to have_text(I18n.t("maint_platform.module_settings.show.payment.title"))
    expect(page).to have_css("[data-payment-gateway-list='true']")
    expect(page).to have_css("[data-module-settings-setting-row='true']", text: "Stripe")
    expect(page).to have_css("button[role='switch'][aria-label='Stripe availability']")
    expect(page).to have_text("stripe")
    expect(page).to have_text(I18n.t("maint_platform.module_settings.show.payment.flows.qr"))
    expect(page).to have_text(I18n.t("maint_platform.module_settings.show.payment.flows.h5"))
  end

  it "localizes known flow chips in zh-CN" do
    gateway = Struct.new(:key, :display_name, :supported_flows).new("alipay", "Alipay", %i[qr card])
    platform_gateway = instance_double(Payments::PlatformGateway, available?: true)

    I18n.with_locale(:"zh-CN") do
      render_gateways([[gateway, platform_gateway]])
    end

    expect(page).to have_text("扫码支付")
    expect(page).to have_text("托管卡支付")
  end

  it "does not upcase an unknown flow key" do
    gateway = Struct.new(:key, :display_name, :supported_flows).new("demo", "Demo", %i[foo_bar])
    platform_gateway = instance_double(Payments::PlatformGateway, available?: true)

    render_gateways([[gateway, platform_gateway]])

    expect(page).to have_text("foo_bar")
    expect(page).not_to have_text("FOO_BAR")
  end

  it "renders the empty section when no gateways are registered" do
    render_gateways([])

    expect(page).to have_text(I18n.t("maint_platform.module_settings.show.payment.empty_title"))
    expect(page).to have_css("[data-module-settings-empty-section='true']")
    expect(page).not_to have_css("[data-payment-gateway-list='true']")
  end
end
