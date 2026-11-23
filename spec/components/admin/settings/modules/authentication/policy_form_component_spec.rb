require "rails_helper"

RSpec.describe Admin::Settings::Modules::Authentication::PolicyFormComponent, type: :component do
  let(:customer) { build_stubbed(:customer, id: 81721200) }

  { registration: "sign_up", recovery: "forget_password" }.each do |policy, endpoint|
    [true, false].each do |enabled|
      it "preserves the #{policy} policy payload when enabled is #{enabled}" do
        render_inline(described_class.new(policy: policy, enabled: enabled, customer: customer))
        expect(page).to have_css("form[action='/#{customer.id}/admin/settings/modules/authentication/#{endpoint}']")
        expect(page).to have_css("input[name='_method'][value='patch']", visible: :all)
        expect(page).to have_css("select[name='setting[enabled]'] option[value='#{enabled}'][selected]")
        expect(page).to have_css("label[for='setting_enabled']")
        expect(page).to have_button("Save", count: 1)
        expect(page).to have_css(".max-w-3xl")
      end
    end
  end

  it "localizes policy consequences" do
    I18n.with_locale(:"zh-CN") do
      render_inline(described_class.new(policy: :registration, enabled: true, customer: customer))
    end
    expect(page).to have_text("允许会员注册")
    expect(page).to have_text("重新启用后恢复")
    expect(page).not_to have_text("Translation missing")
  end
end
