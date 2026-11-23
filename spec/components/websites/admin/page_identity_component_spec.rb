# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Admin::PageIdentityComponent, type: :component do
  def render_identity(record: build_stubbed(:website_page, title: "Our team", slug: "internal-team-path"), **options)
    composer = Websites::Admin::ComposerComponent.new(page: record, **options)
    component_class = described_class
    render_in_view_context do
      form_with(url: "/pages", scope: composer.form_scope) do |form|
        render component_class.new(composer: composer, form: form)
      end
    end
  end

  %w[en zh-CN].each do |locale|
    it "renders only the localized settings label in the collapsed summary in #{locale}" do
      I18n.with_locale(locale) do
        render_identity

        expect(page).to have_css("section[data-identity-panel].hidden", visible: :all)
        expect(page).to have_css("#website-page-identity-heading", text: I18n.t("website.admin.pages.edit.page_settings"), visible: :all)
        expect(page).to have_css("button[data-action='click->website-builder#showOutline:prevent'][aria-label='#{I18n.t("website.admin.pages.edit.back_to_sections")}']", visible: :all)
        expect(page).not_to have_css("details[data-identity-panel]")
      end
    end

    it "gives switches distinct localized names and descriptions in #{locale}" do
      I18n.with_locale(locale) do
        render_identity
        document = Nokogiri::HTML.fragment(rendered_content)

        %w[nav_visible published home].each do |field|
          control = document.at_css("#website_page_#{field}")
          expect(control['role']).to eq('switch')
          expect(document.at_css("##{control['aria-labelledby']}").text).to eq(I18n.t("website.admin.pages.form.#{field}"))
        end
        published = document.at_css('#website_page_published')
        expect(document.at_css("##{published['aria-describedby']}").text).to eq(I18n.t('website.admin.pages.form.published_hint'))
      end
    end

    [ :new, :inner, :home ].each do |state|
      it "omits every slug presentation and parameter on #{state} pages in #{locale}" do
        I18n.with_locale(locale) do
          record = state == :new ? build(:website_page) : build_stubbed(:website_page)
          record.assign_attributes(title: "Our team", slug: "internal-team-path", home: state == :home)
          render_identity(record: record, identity_only: state == :new)

          expect(rendered_content).not_to include("internal-team-path", "website_page[slug]", "website_page_slug")
          expect(page).not_to have_text(:all, I18n.t("website.admin.pages.form.slug"))
          expect(page).not_to have_text(:all, I18n.t("website.admin.pages.form.slug_hint"))
          expect(page).to have_field(I18n.t("website.admin.pages.form.title"), with: "Our team", visible: :all)
        end
      end
    end
  end

  it "groups preferences in full-width divided rows with labelled native controls and adjacent help" do
    render_identity
    document = Nokogiri::HTML.fragment(rendered_content)
    fieldset = document.at_css("fieldset")
    expect(fieldset.at_css("legend").text).to eq(I18n.t("website.admin.pages.form.visibility"))
    expect(fieldset.at_css("div")['class'].split).to include("flex-col", "divide-y")
    expect(fieldset.css("label").size).to eq(3)
    expect(fieldset.css("[class*='grid-cols'], .card")).to be_empty

    %w[nav_visible published home].each do |field|
      label = fieldset.at_css("label[for='website_page_#{field}']")
      expect(label['class'].split).to include("min-h-11", "w-full", "justify-between")
      checkbox = label.at_css("input[type='checkbox']")
      expect(checkbox['id']).to eq(label['for'])
      expect(checkbox['class'].split).to include("peer", "a11y-clip")
      action = field == "home" ? "confirmSetHome" : "markDirty"
      expect(checkbox['data-action']).to eq("change->website-builder##{action}")
      expect(label.at_css("input[type='hidden']")['value']).to eq("0")
      expect(checkbox.next_element['class']).to include("peer-checked:", "peer-focus-visible:")
    end
    published = fieldset.at_css("#website_page_published")
    expect(fieldset.at_css("##{published['aria-describedby']}").text).to eq(I18n.t("website.admin.pages.form.published_hint"))
    expect(document.at_css("#website_page_title")['class'].split).to include("input-field", "h-9")
  end

  [true, false].each do |enabled|
    it "preserves native switch submission values when preferences are #{enabled}" do
      render_identity(record: build_stubbed(:website_page, nav_visible: enabled, published: enabled))

      %w[nav_visible published].each do |field|
        expect(page).to have_field("website_page[#{field}]", type: :checkbox, checked: enabled, disabled: false, visible: :all)
        expect(page).to have_css("input[type='checkbox'][name='website_page[#{field}]'][value='1']", count: 1, visible: :all)
        expect(page).to have_css("input[type='hidden'][name='website_page[#{field}]'][value='0']", count: 1, visible: :all)
      end
    end
  end

  it "keeps the home control checked and disabled with its explanation and a single successful hidden value" do
    render_identity(record: build_stubbed(:website_page, :home))

    expect(page).to have_field("website_page[home]", type: :checkbox, checked: true, disabled: true, visible: :all)
    expect(page).to have_css("input[type='hidden'][name='website_page[home]'][value='1']:not([disabled])", count: 1, visible: :all)
    expect(page).not_to have_css("input[name='website_page[home]'][value='0']", visible: :all)
    expect(page).to have_css("#website_page_home[aria-describedby='website_page_home_hint']", count: 1, visible: :all)
    expect(page).to have_css("#website_page_home_hint", text: I18n.t("website.admin.pages.form.home_locked"), visible: :all)
  end

  it "retains the platform layout technical key" do
    render_identity(record: build_stubbed(:website_layout, key: "article"), kind: :layout)

    expect(page).to have_field("website_layout[key]", with: "article", disabled: true)
    expect(page).to have_field("website_layout[key]", type: :hidden, with: "article", visible: :all)
    expect(page).not_to have_css("fieldset")
  end

  describe "theme select" do
    def theme_select
      page.find("select[name='website_page[theme_key]']", visible: :all)
    end

    it "lets an existing page follow the site theme or pin any preset" do
      render_identity(record: build_stubbed(:website_page, title: "Visit", slug: "visit", theme_key: "midnight"))

      expect(theme_select["data-action"]).to eq("change->website-builder#markDirty")
      expect(theme_select).to have_css("option[value='']", text: I18n.t("website.admin.pages.form.theme_site"), visible: :all)
      expect(theme_select).to have_css("option[value='midnight'][selected]", visible: :all)
      expect(theme_select).to have_css("option", count: Websites::ThemePresets.keys.size + 1, visible: :all)
      expect(theme_select).not_to have_css("option[value='layout']", visible: :all)
      expect(page).to have_css("##{theme_select['aria-describedby']}", text: I18n.t("website.admin.pages.form.theme_hint"), visible: :all)
    end

    it "offers the layout's paired theme on the new-page form" do
      render_identity(record: WebsitePage.new, identity_only: true)

      expect(theme_select).to have_css("option[value='layout']", text: I18n.t("website.admin.pages.form.theme_layout"), visible: :all)
      expect(theme_select).to have_css("option[value=''][selected]", visible: :all)
    end

    it "names the catalog pairing as the layout default" do
      render_identity(record: build_stubbed(:website_layout, key: "article", theme_key: nil), kind: :layout)

      select = page.find("select[name='website_layout[theme_key]']", visible: :all)
      paired = Websites::ThemePresets.name(Websites::ThemePairing.for_layout("article"))
      expect(select).to have_css("option[value='']", text: I18n.t("website.admin.pages.form.theme_paired", name: paired), visible: :all)
      expect(page).to have_text(I18n.t("website.platform.layouts.form.theme_hint"))
    end
  end
end
