# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Entities::PersonLinkComponent, type: :component do
  let(:customer) { create(:customer) }
  let(:entity) { create(:entity, customer: customer) }
  let(:entry) { create(:entity_entry, customer: customer, entity: entity) }
  let(:user) { nil }
  let(:writable) { true }

  def render_card
    render_inline(described_class.new(entity: entity, entry: entry, user: user, writable: writable))
  end

  def link_path
    "/#{customer.id}/admin/entities/#{entity.id}/entries/#{entry.id}/person_link"
  end

  context "when not linked and writable" do
    before { render_card }

    it "renders the Account card with the helper and picker" do
      card = page.find("section[aria-labelledby='entry-account-heading']")
      aggregate_failures do
        expect(card).to have_css("h2#entry-account-heading", text: I18n.t("comp_admin.person_link.heading"))
        expect(card).not_to have_text(I18n.t("comp_admin.person_link.badge_not_linked"))
        expect(card).to have_text(I18n.t("comp_admin.person_link.helper"))
        expect(card["data-controller"]).to eq("person-link-picker")
        expect(card).to have_css("[data-person-link-picker-target='trigger'][aria-haspopup='listbox'][aria-expanded='false']",
                                 text: I18n.t("comp_admin.person_link.link_action"))
        expect(card).to have_css("[data-person-link-picker-target='search'][role='combobox'][aria-autocomplete='list']")
        expect(card).to have_css("[data-person-link-picker-target='list'][role='listbox']")
        expect(card).to have_css("[data-person-link-picker-target='status'][role='status'][aria-live='polite']")
        expect(card).to have_css("form[action='#{link_path}'] input[name='user_id']", visible: :all)
        expect(card).to have_css("[data-person-link-picker-target='confirm'] button[type='submit']",
                                 text: I18n.t("comp_admin.person_link.confirm_submit"), visible: :all)
        expect(card).to have_css("[data-action='person-link-picker#cancel']", text: I18n.t("common.actions.cancel"), visible: :all)
        expect(card["data-person-link-picker-candidates-url-value"]).to eq("#{link_path}/candidates.json")
      end
    end

    it "does not clip the absolutely positioned picker panel" do
      card = page.find("section[aria-labelledby='entry-account-heading']")
      expect(card[:class].split).not_to include("overflow-hidden")
    end
  end

  context "when linked and writable" do
    let(:user) { create(:user, customer: customer, first_name: "Ada", last_name: "Lovelace") }

    before { render_card }

    it "links the linked user's name to their user detail page, with no separate View user action or unlink" do
      card = page.find("section[aria-labelledby='entry-account-heading']")
      user_path = "/#{customer.id}/admin/modules/authentication/users/#{user.id}"
      aggregate_failures do
        expect(card).not_to have_css(".badge", text: I18n.t("comp_admin.person_link.badge_linked"))
        expect(card).to have_link("Ada Lovelace", href: user_path)
        expect(card).to have_css("a", count: 1)
        expect(card).not_to have_link(I18n.t("comp_admin.person_link.view_user"))
        expect(card).to have_text(user.email)
        expect(card).not_to have_css("[data-controller='person-link-picker']")
        expect(card).not_to have_text(I18n.t("comp_admin.person_link.helper"))
        expect(card).not_to have_css("form, [data-turbo-confirm]")
        expect(card).not_to have_text(I18n.t("comp_admin.person_link.unlink_action"))
      end
    end

    it "shows the linked user's initials as a decorative avatar" do
      expect(page).to have_css("section[aria-labelledby='entry-account-heading'] span[aria-hidden='true']", text: "AL")
    end
  end

  context "when linked to a deactivated user" do
    let(:user) { create(:user, :inactive, customer: customer, first_name: "Ada", last_name: "Lovelace") }

    before { render_card }

    it "adds the deactivated warning without a separate linked status" do
      card = page.find("section[aria-labelledby='entry-account-heading']")
      aggregate_failures do
        expect(card).not_to have_css(".badge", text: I18n.t("comp_admin.person_link.badge_linked"))
        expect(card).to have_css(".badge", text: I18n.t("comp_admin.person_link.badge_deactivated"))
        expect(card).to have_text(I18n.t("comp_admin.person_link.deactivated_note"))
        expect(card).to have_link("Ada Lovelace", href: "/#{customer.id}/admin/modules/authentication/users/#{user.id}")
        expect(card).not_to have_link(I18n.t("comp_admin.person_link.view_user"))
      end
    end
  end

  context "when read-only and not linked" do
    let(:writable) { false }

    before { render_card }

    it "shows the empty account, with no picker or actions" do
      card = page.find("section[aria-labelledby='entry-account-heading']")
      aggregate_failures do
        expect(card).not_to have_text(I18n.t("comp_admin.person_link.badge_not_linked"))
        expect(card).to have_text(I18n.t("common.labels.em_dash"))
        expect(card).not_to have_css("[data-controller='person-link-picker']")
        expect(card).not_to have_text(I18n.t("comp_admin.person_link.helper"))
        expect(card).not_to have_css("button")
        expect(card).not_to have_css("form")
      end
    end
  end

  context "when read-only and linked" do
    let(:writable) { false }
    let(:user) { create(:user, :inactive, customer: customer, first_name: "Ada", last_name: "Lovelace") }

    before { render_card }

    it "shows the linked user, linked to their detail page, and the deactivated note" do
      card = page.find("section[aria-labelledby='entry-account-heading']")
      aggregate_failures do
        expect(card).not_to have_css(".badge", text: I18n.t("comp_admin.person_link.badge_linked"))
        expect(card).to have_css(".badge", text: I18n.t("comp_admin.person_link.badge_deactivated"))
        expect(card).to have_link("Ada Lovelace", href: "/#{customer.id}/admin/modules/authentication/users/#{user.id}")
        expect(card).to have_text(I18n.t("comp_admin.person_link.deactivated_note"))
        expect(card).not_to have_css("[data-turbo-confirm]")
        expect(card).not_to have_text(I18n.t("comp_admin.person_link.unlink_action"))
        expect(card).not_to have_css("form")
      end
    end
  end

  it "renders copy from I18n in zh-CN" do
    I18n.with_locale(:"zh-CN") { render_card }

    expect(page).to have_css("h2", text: I18n.t("comp_admin.person_link.heading", locale: :"zh-CN"))
    expect(page).not_to have_text(I18n.t("comp_admin.person_link.badge_not_linked", locale: :"zh-CN"))
    expect(page).to have_text(I18n.t("comp_admin.person_link.helper", locale: :"zh-CN"))
    expect(page).to have_text(I18n.t("comp_admin.person_link.link_action", locale: :"zh-CN"))
  end
end
