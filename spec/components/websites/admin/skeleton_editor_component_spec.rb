# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Admin::SkeletonEditorComponent, type: :component do
  let(:skeleton) do
    instance_double(
      WebsiteSkeleton,
      key: "presence",
      name: "Presence",
      description: "Classic introduction site",
      page_list: [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "presence_home",
          "sections" => []
        },
        {
          "title" => "About",
          "slug" => "about",
          "home" => false,
          "nav_visible" => true,
          "role" => "about",
          "layout_key" => "presence_about",
          "sections" => []
        }
      ]
    )
  end

  let(:layouts) do
    [
      instance_double(WebsiteLayout, key: "presence_home", display_name: "Presence home"),
      instance_double(WebsiteLayout, key: "presence_about", display_name: "Presence about")
    ]
  end

  it "renders identity fields, category, inspired-by credit, and page drafts" do
    render_inline(described_class.new(
      skeleton: skeleton,
      layouts: layouts,
      form_url: "/skeletons/presence",
      customer_id: 81_721_200
    ))

    expect(page).to have_css("form#website-skeleton-form")
    expect(page).to have_field("website_skeleton_name", with: "Presence")
    expect(page).to have_text(I18n.t("website.skeletons.categories.business"))
    expect(page).to have_text(
      I18n.t("website.skeletons.inspired_by_format", brand: I18n.t("website.skeletons.presence.inspired_by"))
    )
    expect(page).to have_text(I18n.t("website.platform.skeletons.form.page_index", index: 1))
    expect(page).to have_text(I18n.t("website.platform.skeletons.form.page_index", index: 2))
    expect(page).to have_css("[data-skeleton-page='0']")
    expect(page).to have_css("[data-skeleton-page='1']")
    expect(page).to have_button(I18n.t("website.platform.skeletons.form.add_page"))
  end

  it "selects the skeleton's pinned theme and names the catalog pairing as the default" do
    allow(skeleton).to receive(:theme_key).and_return("aurora")
    render_inline(described_class.new(skeleton: skeleton, layouts: layouts, form_url: "/skeletons/presence", customer_id: 81_721_200))

    select = page.find("select#website_skeleton_theme_key")
    paired = Websites::ThemePresets.name(Websites::ThemePairing.for_skeleton("presence"))
    expect(select).to have_css("option[value='']", text: I18n.t("website.admin.pages.form.theme_paired", name: paired))
    expect(select).to have_css("option[value='aurora'][selected]")
    expect(page).to have_css("#website_skeleton_theme_key_hint", text: I18n.t("website.platform.skeletons.form.theme_hint"))
  end
end
