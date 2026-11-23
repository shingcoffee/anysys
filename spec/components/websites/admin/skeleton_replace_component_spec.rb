# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Admin::SkeletonReplaceComponent, type: :component do
  let(:website) { build_stubbed(:website, skeleton_key: "presence") }
  let(:replace_url) { "/81721200/admin/settings/modules/website/skeleton" }

  def render_replace(**opts)
    render_inline(
      described_class.new(
        website: website,
        replace_url: replace_url,
        **opts
      )
    )
  end

  it "renders starter cards, current caption, and a turbo-confirm per card" do
    render_replace(skeletons: Websites::Skeletons.keys)

    expect(page).to have_css("[data-skeleton-replace='true']")
    expect(page).to have_css("h2.section-header", text: I18n.t("website_settings.starter.heading"))
    expect(page).to have_css("details:not([open]) > summary", text: I18n.t("website_settings.starter.browse"))
    expect(page).to have_css("article[data-skeleton-key] h3[data-starter-name]", visible: :all, count: Websites::Skeletons.keys.size)
    expect(page).to have_css("article[data-skeleton-key] [data-catalog-thumbnail]", visible: :all, count: Websites::Skeletons.keys.size)
    expect(page).to have_css("[data-current-starter='presence'] [data-catalog-thumbnail]")
    expect(page).to have_css("#website-replacement-consequences.bg-warning-subtle", visible: :all)
    expect(page).to have_text(I18n.t("website_settings.starter.description"))
    expect(page).to have_text(I18n.t("website.admin.settings.skeleton.current", name: "Presence"))
    expect(page).to have_text(:all, I18n.t("website.admin.settings.skeleton.current_badge"))
    expect(page).not_to have_select("skeleton_key")

    Websites::Skeletons.keys.each do |key|
      expect(page).to have_css("[data-skeleton-key='#{key}']", visible: :all)
      expect(page).to have_css("input[type='hidden'][name='skeleton_key'][value='#{key}']", visible: :hidden)
      expect(page).to have_text(:all, I18n.t("website.skeletons.#{key}.name"))
    end

    expect(page).to have_css("article[data-skeleton-key='presence'].border-accent", visible: :all)
    expect(page).to have_css("form[action='#{replace_url}'][data-turbo-confirm]", visible: :all)
    expect(page).to have_css("form[data-turbo-confirm*='Presence']", visible: :all)
    expect(page).to have_button(I18n.t("website_settings.starter.replace"), visible: :all)
    expect(page).to have_css("button.btn-danger", visible: :all)
    expect(page).to have_text(:all, I18n.t("website.skeletons.categories.business"))
  end

  it "marks cinematic current and interpolates that name into confirm" do
    website.skeleton_key = "cinematic"
    render_replace(skeletons: %w[presence cinematic])

    expect(page).to have_css("article[data-skeleton-key='cinematic']", visible: :all)
    expect(page).to have_text(I18n.t("website.admin.settings.skeleton.current", name: "Cinematic"))
    expect(page).to have_css("form[data-turbo-confirm*='Cinematic']", visible: :all)
    expect(page).to have_text(:all, I18n.t("website.admin.settings.skeleton.current_badge"))
  end

  it "filters unknown skeleton keys from the picker" do
    render_replace(skeletons: %w[presence unknown cinematic])

    expect(page).to have_css("[data-skeleton-key='presence']", visible: :all)
    expect(page).to have_css("[data-skeleton-key='cinematic']", visible: :all)
    expect(page).not_to have_css("[data-skeleton-key='unknown']", visible: :all)
  end

  it "renders catalog-shaped rows with customer-facing page names" do
    row = OpenStruct.new(
      key: "presence",
      name: "Presence",
      description: "Classic introduction site",
      pages: [{ "role" => "home" }, { "title" => "About" }]
    )
    render_replace(skeletons: [row])

    expect(page).to have_css("[data-skeleton-key='presence']", visible: :all)
    expect(page).to have_text(:all, "Classic introduction site")
    expect(page).to have_text(:all, I18n.t("website.platform.skeletons.pages.home"))
    expect(page).to have_text(:all, "About")
  end

  it "uses display_name and display_description when the row exposes them" do
    row = OpenStruct.new(
      key: "presence",
      display_name: "Harbor Presence",
      display_description: "A custom starter",
      page_list: [{ "role" => "contact" }]
    )

    render_replace(skeletons: [row])

    expect(page).to have_text("Current starter: Harbor Presence")
    expect(page).to have_text(:all, "A custom starter")
    expect(page).to have_text(:all, I18n.t("website.platform.skeletons.pages.contact"))
    expect(page).to have_css("form[data-turbo-confirm*='Harbor Presence']", visible: :all)
  end

  it "explains all replacement consequences and keeps confirmation on each separate POST" do
    render_replace(skeletons: %w[presence cinematic])

    %w[deletes_pages resets_appearance unpublished_pages unsaved_changes].each do |key|
      expect(page).to have_text(:all, I18n.t("website_settings.starter.#{key}"))
    end
    page.all("form", visible: :all).each do |form|
      key = form.find("input[name='skeleton_key']", visible: :hidden).value
      expect(form[:method]).to eq("post")
      expect(form[:action]).to eq(replace_url)
      expect(form[:"data-turbo-confirm"]).to eq(I18n.t("website_settings.starter.confirm", name: I18n.t("website.skeletons.#{key}.name")))
      expect(form[:"aria-describedby"]).to eq("website-replacement-consequences")
      expect(form).not_to have_css("input[name^='website[']", visible: :all)
    end
  end

  it "does not mark the first template as current when the saved template is unavailable" do
    website.skeleton_key = "removed_internal_key"
    render_replace(skeletons: %w[presence cinematic])

    expect(page).not_to have_css("article.border-accent", visible: :all)
    expect(page).not_to have_text(:all, "removed_internal_key")
    expect(page).to have_text(I18n.t("website_settings.starter.unavailable"))
  end

  it "uses a readable title for custom page roles rather than exposing their keys" do
    row = OpenStruct.new(key: "presence", pages: [{ "role" => "custom_internal_key", "title" => "Our work" }])
    render_replace(skeletons: [row])

    expect(page).to have_text(:all, "Our work")
    expect(page).not_to have_text(:all, "custom_internal_key")
  end

  it "keeps replacement forms outside the ordinary settings form" do
    render_inline(Websites::Admin::SettingsFormComponent.new(website: website, customer_id: "81721200", layouts: [])) do
      described_class.new(website: website, skeletons: %w[presence], replace_url: replace_url).render_in(vc_test_controller.view_context)
    end

    expect(page).to have_css("form#website-settings-form", count: 1)
    expect(page).to have_css("form[action='#{replace_url}']", count: 1, visible: :all)
    expect(page).not_to have_css("form#website-settings-form input[name='skeleton_key']", visible: :all)
    expect(page).not_to have_css("form#website-settings-form form", visible: :all)
  end

  it "localizes the consequence summary and confirmation in Chinese" do
    I18n.with_locale(:"zh-CN") do
      render_replace(skeletons: %w[presence])

      expect(page).to have_css("h2", text: I18n.t("website_settings.starter.heading"))
      expect(page).to have_text(:all, I18n.t("website_settings.starter.resets_appearance"))
      expect(page).to have_css("form[data-turbo-confirm='#{I18n.t("website_settings.starter.confirm", name: I18n.t("website.skeletons.presence.name"))}']", visible: :all)
      expect(page).not_to have_css(".translation_missing", visible: :all)
    end
  end
end
