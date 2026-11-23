# frozen_string_literal: true

require "rails_helper"

RSpec.describe HelpMenuComponent, type: :component do
  include Rails.application.routes.url_helpers

  let(:customer) { create(:customer) }
  let(:admin) { create(:user, :admin, customer: customer) }

  def render_help(user: admin, customer_id: customer.id)
    render_inline(described_class.new(user: user, customer_id: customer_id))
  end

  it "renders a Help button and the three Get Help actions" do
    render_help
    expect(page).to have_css("button[aria-label='Help']")
    expect(page).to have_button("Notify platform owner")
    expect(page).to have_button("Email support")
    expect(page).to have_link("Documentation", href: admin_help_docs_path(customer.id, locale: :en))
    expect(page).to have_css("a[role='menuitem'][data-action='click->help-menu#close']", text: "Documentation")
    expect(page).not_to have_css("a[target='_blank']", text: "Documentation")
    expect(page).not_to have_css("a[rel]", text: "Documentation")
  end

  it "hides Notify platform owner for the platform owner" do
    owner = find_or_create_platform_owner
    render_help(user: owner, customer_id: Authentication::User::PLATFORM_CUSTOMER_ID)
    expect(page).not_to have_button("Notify platform owner")
    expect(page).to have_button("Email support")
    expect(page).to have_link("Documentation", href: admin_help_docs_path(Authentication::User::PLATFORM_CUSTOMER_ID, locale: :en))
    expect(page).not_to have_css("a[target='_blank']", text: "Documentation")
  end

  it "retains the visited customer context for the platform owner" do
    render_help(user: find_or_create_platform_owner)

    expect(page).to have_link("Documentation", href: admin_help_docs_path(customer.id, locale: :en))
  end

  it "hides Documentation for a member" do
    render_help(user: create(:user, :member, customer: customer))

    expect(page).not_to have_link("Documentation")
  end

  it "hides Documentation for an anonymous user with a customer context" do
    render_help(user: nil)

    expect(page).not_to have_link("Documentation")
  end

  it "hides Documentation without a customer context" do
    render_help(customer_id: nil)

    expect(page).not_to have_link("Documentation")
  end

  it "localizes the internal documentation entry" do
    I18n.with_locale(:"zh-CN") do
      render_help

      expect(page).to have_link("文档", href: admin_help_docs_path(customer.id, locale: :"zh-CN"))
      expect(page).to have_content("客户指南与操作说明")
    end
  end

  it "does not render About or Keyboard shortcuts" do
    render_help
    expect(page).not_to have_button("Keyboard shortcuts")
    expect(page).not_to have_button("About")
    expect(page).not_to have_link("Contact support")
  end
end
