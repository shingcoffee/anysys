# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Admin::SettingsFormComponent, type: :component do
  let(:form_url) { "/81721200/admin/settings/modules/website/site" }
  let(:website) do
    build_stubbed(
      :website,
      name: "Acme Institute",
      tagline: "Craft, research, and public programs",
      published: false,
      skeleton_key: "presence",
      theme: Website::DEFAULT_THEME.dup,
      seo: { "title" => "Acme", "description" => "Hello" },
      footer: {
        "blurb" => "Visit us downtown.",
        "columns" => [
          {
            "heading" => "Visit",
            "links" => [{ "label" => "Home", "url" => "/" }]
          }
        ]
      }
    )
  end

  def render_form(record = website, **opts)
    render_inline(
      described_class.new(
        website: record,
        customer_id: "81721200",
        form_url: form_url,
        **opts
      )
    )
  end

  describe "missing site" do
    it "renders the missing-site alert and no form" do
      render_form(nil)

      expect(page).to have_text(I18n.t("website.admin.settings.missing_site"))
      expect(page).not_to have_css("form#website-settings-form")
      expect(page).not_to have_css("[data-controller='website-theme-picker']")
    end
  end

  describe "default form" do
    before { render_form }

    it "renders customer settings sections with the theme picker and native section navigation" do
      expect(page).to have_css("[data-website-settings='true'][data-controller='website-theme-picker']")
      expect(page).to have_css("form#website-settings-form[action='#{form_url}']")
      expect(page).not_to have_css("form#website-settings-form[data-controller]")
      expect(page).to have_field("website[name]", with: "Acme Institute")
      expect(page).to have_field("website[tagline]", with: "Craft, research, and public programs")
      expect(page).to have_css("h2", text: I18n.t("website.admin.settings.identity.heading"))
      expect(page).to have_text(I18n.t("website.admin.settings.identity.description"))
      expect(page).to have_css("h2", text: I18n.t("website.admin.settings.theme.appearance"))
      expect(page).to have_css("h2", text: I18n.t("website_settings.search.heading"))
      expect(page).to have_css("h2", text: I18n.t("website.admin.settings.footer.heading"))
      expect(page).to have_css("#publish h2", text: I18n.t("website_settings.publishing.heading"))
      expect(page).not_to have_css("details > summary", text: I18n.t("website.admin.settings.jump"))
      expect(page).to have_css("nav.sticky[data-settings-nav][aria-label='#{I18n.t("website.admin.settings.jump")}']")
      expect(page.all("nav[data-settings-nav] a").map { |link| link[:href] }.first(5)).to eq(%w[
        #website-settings-publish-heading #website-settings-identity-heading #website-settings-theme-heading
        #website-settings-seo-heading #website-settings-footer-heading
      ])
      expect(page).to have_css("nav a[href='#website-settings-identity-heading']", text: I18n.t("website.admin.settings.identity.heading"), visible: :all)
      expect(page).not_to have_css("nav a[href='#website-settings-skeleton-heading']", visible: :all)
      expect(page).to have_css("nav a[data-website-theme-picker-target='nav'][data-action='click->website-theme-picker#highlight']", visible: :all)
      expect(page).to have_css("h2.section-header", text: I18n.t("website.admin.settings.identity.heading"))
      expect(page).to have_css("input.input-field.h-10#website_name")
      expect(page).to have_css("label.form-label", text: I18n.t("website.admin.settings.identity.name"))
    end

    it "keeps all theme radio values and live preview hooks" do
      expect(page).to have_css("input[type='radio'].sr-only.peer[name='website[theme][appearance]'][value='light'][checked]")
      expect(page).to have_css("input[type='radio'].sr-only.peer[name='website[theme][appearance]'][value='dark']")
      expect(page).to have_css("input[type='radio'][name='website[theme][accent]'][value='azure'][checked]")
      expect(page).to have_css("input[type='radio'][name='website[theme][accent]'][value='violet']")
      expect(page).to have_css("input[type='radio'][name='website[theme][accent]'][value='copper']")
      expect(page).to have_css("input[type='radio'][name='website[theme][type]'][value='sans'][checked]")
      expect(page).to have_css("input[type='radio'][name='website[theme][density]'][value='spacious'][checked]")
      expect(page).to have_css("input[data-website-theme-picker-target='token'][data-token='appearance']")
      expect(page).to have_text(I18n.t("website.admin.settings.theme.light"))
      expect(page).to have_css("[data-theme-preview-swatch][data-accent='azure']")
      expect(page).to have_text(I18n.t("website.admin.settings.theme.preview.headline"))
      described_class::THEME_GROUPS.each do |group|
        group[:values].each do |value|
          expect(page).to have_css("input[name='website[theme][#{group[:token]}]'][value='#{value}'][data-token='#{group[:token]}'][data-website-theme-picker-target='token']")
        end
      end
    end

    it "renders SEO fields and footer column arrays" do
      expect(page).to have_field("website[seo][title]", with: "Acme")
      expect(page).to have_field("website[seo][description]", with: "Hello")
      expect(page).to have_field("website[footer][blurb]", with: "Visit us downtown.")
      expect(page).to have_field("website[footer][columns][0][heading]", with: "Visit")
      expect(page).to have_field("website[footer][columns][0][links][0][label]", with: "Home")
      expect(page).to have_css("ol[data-controller='countable-items-reorder']")
      expect(page).to have_css("button[data-countable-items-reorder-target='handle'][aria-label]")
      expect(page).to have_css("button[data-action='click->countable-items-reorder#moveUp']")
      expect(page).to have_css("[data-footer-add-column='true']")
    end

    it "renders the publish checkbox bound to Save and an unpublished pill" do
      expect(page).to have_css("input[type='checkbox'][name='website[published]'][value='1']")
      expect(page).to have_css("input[type='checkbox'][name='website[published]'][aria-labelledby='website_published_label']")
      expect(page).not_to have_css("input[type='checkbox'][name='website[published]'][checked]")
      expect(page).to have_text(I18n.t("website_settings.publishing.hint"))
      expect(page).to have_text(I18n.t("website.admin.settings.publish.status_off"))
    end

    it "renders the publish control as a switch with the site address in the status card" do
      expect(page).to have_css("#publish[data-site-status='hidden'] input[type='checkbox'][role='switch'].peer.sr-only#website_published[aria-describedby='website_published_hint']")
      expect(page).to have_css("#publish input[type='hidden'][name='website[published]'][value='0']", visible: :hidden)
      expect(page).to have_css("#publish [data-page-address]", text: "/")
      expect(page).not_to have_css("#publish [data-page-address] a")
      expect(page).to have_text(I18n.t("website.admin.pages.edit.address_hidden"))
    end

    it "draws theme choices as visual options and keeps SEO guidance next to the fields" do
      expect(page).to have_css("label[data-theme-option='accent'] input#website_theme_accent_azure + span.bg-sky-500")
      expect(page).to have_css("label[data-theme-option='type']", text: I18n.t("website.admin.settings.theme.specimen"), count: Websites::Theme::TYPES.size)
      expect(page).to have_css("label[data-theme-option='appearance'] input#website_theme_appearance_dark ~ span .bg-neutral-950")
      expect(page).to have_css("input#website_seo_title[aria-describedby='website_seo_title_hint']")
      expect(page).to have_css("#website_seo_description_hint", text: I18n.t("website_settings.search.description_hint"))
    end

    it "leads with publishing, then identity, before the longer appearance and footer controls" do
      section_ids = page.all("form > section").map { |section| section[:id] }
      expect(section_ids.first(2)).to eq(%w[publish website-settings-identity])
      expect(page).to have_css("section#website-settings-identity[aria-labelledby='website-settings-identity-heading'][data-website-theme-picker-target='section']")
      expect(page).to have_css("form#website-settings-form input[name='_method'][value='patch']", visible: :hidden)
      expect(page).not_to have_css("form[data-turbo-confirm]", visible: :all)
    end
  end

  it "checks the publish box and shows the published pill when the site is published" do
    website.published = true
    render_form

    expect(page).to have_css("input[type='checkbox'][name='website[published]'][checked]")
    expect(page).to have_text(I18n.t("website.admin.settings.publish.status_on"))
    expect(page).to have_css("#publish[data-site-status='live'] [data-page-address] a[href='/'][target='_blank']")
    expect(page).to have_link("Manage page shortcuts", href: "/81721200/admin/maintenance/page_shortcuts")
  end

  it "shows inline errors from the website record" do
    website.errors.add(:name, "can't be blank")
    render_form

    expect(page).to have_css("input[name='website[name]'][aria-invalid='true']")
    expect(page).to have_css("input[aria-describedby='website-name-error']")
    expect(page).to have_css("p.text-danger", text: /blank/)
  end

  it "does not pad a fourth add-column slot when four columns already exist" do
    website.footer = {
      "columns" => Array.new(4) { |i| { "heading" => "Col #{i}", "links" => [] } }
    }
    render_form

    expect(page).to have_css("li[data-countable-items-reorder-target='row']", count: 4)
    expect(page).not_to have_css("[data-footer-add-column='true']")
  end

  it "yields a block after the settings form" do
    render_inline(
      described_class.new(website: website, customer_id: "81721200", form_url: form_url)
    ) { "<p data-yielded='true'>starter</p>".html_safe }

    expect(page).to have_css("[data-yielded='true']", text: "starter")
    expect(page).not_to have_css("form [data-yielded='true']")
    expect(page).to have_css("nav a[href='#website-settings-skeleton-heading']", visible: :all)
  end

  it "preserves customer footer values, blank addition slots, and ordering payloads" do
    website.footer = {
      "columns" => [
        { "heading" => "Support", "links" => [{ "label" => "Contact", "url" => "/contact" }] },
        { "heading" => "Visit", "links" => Array.new(8) { |i| { "label" => "Link #{i}", "url" => "/#{i}" } } }
      ]
    }
    render_form

    expect(page).to have_field("website[footer][columns][0][links][0][url]", with: "/contact")
    expect(page).to have_field("website[footer][columns][0][links][1][label]", with: "")
    expect(page).to have_field("website[footer][columns][1][links][7][url]", with: "/7")
    expect(page).not_to have_field("website[footer][columns][1][links][8][label]")
    expect(page).to have_field("website[footer][columns][2][heading]")
    expect(page).to have_css("input[data-countable-items-reorder-target='positionInput'][value='1']", visible: :hidden)
    expect(page).to have_text(I18n.t("website_settings.footer.editing_hint"))
  end

  it "preserves all layout choices and the selected value behind readable names" do
    layouts = [OpenStruct.new(key: "inner_a", display_name: "Simple page"), OpenStruct.new(key: "inner_b", display_name: "Editorial page")]
    website.default_layout_key = "inner_b"
    render_form(layouts: layouts)

    expect(page).to have_select("website[default_layout_key]", options: ["Simple page", "Editorial page"], selected: "Editorial page")
    expect(page).to have_css("option[value='inner_b'][selected]", text: "Editorial page")
    expect(page).to have_css("h2", text: I18n.t("website_settings.page_defaults"))
    expect(page).not_to have_text("inner_b")
  end

  it "groups default layout choices by starter family with the site's own starter first" do
    layouts = %w[article presence_home cinematic_home].map { |key| OpenStruct.new(key: key, display_name: key.titleize) }
    render_form(layouts: layouts)

    groups = page.all("select#website_default_layout_key optgroup").map { |group| group[:label] }
    expect(groups).to eq([I18n.t("website.skeletons.presence.name"), I18n.t("website.skeletons.cinematic.name"), I18n.t("website.admin.pages.new.filters.general")])
    expect(page).to have_css("optgroup[label='#{I18n.t("website.admin.pages.new.filters.general")}'] option[value='article']")
  end

  it "omits the page defaults link when no layouts are available" do
    render_form(layouts: [])

    expect(page).not_to have_css("#website-settings-layout")
    expect(page).not_to have_css("nav a[href='#website-settings-layout-heading']", visible: :all)
  end

  describe "theme preset gallery" do
    def preset_radio(key)
      page.find("input#website_theme_preset_#{key}", visible: :all)
    end

    it "offers every preset with its token set and loads the font library" do
      render_form

      expect(page).to have_css("input[name='website[theme][preset]']", count: Websites::ThemePresets.keys.size, visible: :all)
      radio = preset_radio("midnight")
      expect(JSON.parse(radio["data-tokens"])).to eq(Websites::ThemePresets.tokens("midnight"))
      expect(radio["data-action"]).to eq("change->website-theme-picker#applyPreset")
      expect(radio["data-website-theme-picker-target"]).to eq("preset")
      expect(page).to have_text(Websites::ThemePresets.name("midnight"))
      expect(page).to have_css("link[rel='stylesheet'][href='#{Websites::Fonts.stylesheet_url(Websites::Fonts.keys)}']", visible: :all)
      %w[corners neutral].each do |token|
        expect(page).to have_css("input[data-token='#{token}'][data-website-theme-picker-target='token']", visible: :all)
      end
    end

    it "checks the stored preset and flags it customized once a token drifts" do
      stored = Websites::ThemePresets.theme("midnight").to_stored
      render_form(build_stubbed(:website, theme: stored))
      expect(preset_radio("midnight")).to be_checked
      expect(page).to have_css("[data-website-theme-picker-target='customized'][data-preset='midnight'].hidden", visible: :all)

      render_form(build_stubbed(:website, theme: stored.merge("accent" => "rose")))
      expect(preset_radio("midnight")).to be_checked
      expect(page).to have_css("[data-website-theme-picker-target='customized'][data-preset='midnight']:not(.hidden)")
    end
  end

  it "renders Chinese customer labels while preserving field names and values" do
    I18n.with_locale(:"zh-CN") do
      render_form

      expect(page).to have_css("h2", text: I18n.t("website_settings.search.heading"))
      expect(page).to have_field(I18n.t("website_settings.publishing.label"), type: "checkbox")
      expect(page).to have_field("website[name]", with: "Acme Institute")
      expect(page).not_to have_css(".translation_missing", visible: :all)
    end
  end
end
