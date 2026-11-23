# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Admin::ComposerComponent, type: :component do
  ComposerPage = Struct.new(:title, :slug, :home, :nav_visible, :published, :sections, :layout_key, keyword_init: true) do
    def home? = !!home
    def nav_visible? = nav_visible.nil? ? true : nav_visible
    def published? = !!published
  end

  def page_for(**attrs)
    ComposerPage.new(
      title: "About",
      slug: "about",
      home: false,
      nav_visible: true,
      published: false,
      sections: [],
      **attrs
    )
  end

  def render_composer(page: page_for, preview_url: nil, form_url: "/81721200/admin/modules/website/pages/1", **opts)
    render_inline(described_class.new(page: page, form_url: form_url, preview_url: preview_url, **opts))
  end

  [true, false].each do |embedded|
    it "propagates target headline context through the #{embedded ? 'embedded' : 'workspace'} list and unlocked templates" do
      site = Website.new(id: 7, customer_id: 81_721_200)
      record = WebsitePage.new(website_id: 7, customer_id: 81_721_200, home: true, sections: [
        { id: 'hero', type: 'hero_centered', props: { headline: "Your business.\nBuilt your way." } }
      ])
      context = Websites::HomeSite::Presentation.for(website: site, page: record)
      render_composer(page: record, presentation: context, embedded: embedded, structure_locked: false)
      dom = Nokogiri::HTML.fragment(rendered_content)
      headline = dom.at_css('[data-website-builder-target="list"] textarea[data-prop="headline"]')
      expect(headline.text).to eq("Your business.\nBuilt your way.")
      expect(dom.css('[data-website-builder-target="list"] input[data-prop="headline"]')).to be_empty
      template = dom.at_css('template[data-section-template="hero_centered"]')
      expect(template.at_css('textarea[data-prop="headline"]')).to be_present
      expect(dom.at_css('[data-website-builder-target="json"]')['value']).to include('Your business.\\nBuilt your way.')
    end
  end

  it 'keeps layout editors single-line even if supplied a marketing context' do
    site = Website.new(id: 7, customer_id: 81_721_200)
    record = WebsitePage.new(website_id: 7, customer_id: 81_721_200, home: true)
    context = Websites::HomeSite::Presentation.for(website: site, page: record)
    layout = WebsiteLayout.new(name: 'Layout', sections: [{ id: 'hero', type: 'hero_centered', props: { headline: 'Layout' } }])
    render_composer(page: layout, kind: :layout, presentation: context)
    expect(page).to have_css('input[data-prop="headline"][value="Layout"]', visible: :all)
    expect(page).not_to have_css('textarea[data-prop="headline"]', visible: :all)
  end

  it 'cannot enable multiline headlines on another tenant or extra page with an explicit target context' do
    site = Website.new(id: 7, customer_id: 81_721_200)
    target_page = WebsitePage.new(website_id: 7, customer_id: 81_721_200, home: true)
    context = Websites::HomeSite::Presentation.for(website: site, page: target_page)
    [
      WebsitePage.new(website_id: 99, customer_id: 42, home: true),
      WebsitePage.new(website_id: 7, customer_id: 81_721_200, slug: 'extra')
    ].each do |record|
      record.sections = [{ id: 'hero', type: 'hero_centered', props: { headline: 'Owner headline' } }]
      render_composer(page: record, presentation: context)
      expect(page).to have_css('input[data-prop="headline"][value="Owner headline"]', visible: :all)
      expect(page).not_to have_css('textarea[data-prop="headline"]', visible: :all)
    end
  end

  it "renders the Stimulus host form with identity fields and hidden sections JSON" do
    render_composer

    expect(page).to have_css("form#website-page-form[data-controller='website-builder']")
    expect(page).to have_css("[data-action*='website-builder#reloadPreview']")
    expect(page).to have_field("website_page[title]", with: "About")
    expect(page).not_to have_css("[name='website_page[slug]']", visible: :all)
    expect(page).to have_text(I18n.t("website.admin.pages.form.visibility"))
    expect(page).to have_css("#website-page-identity-heading")
    expect(page).to have_field("website_page[sections_json]", type: :hidden, visible: :hidden)
    expect(page).to have_css("[data-website-builder-target='json']", visible: :all)
    expect(page).to have_css("[data-website-builder-target='list']")
    expect(page).to have_css("[data-website-builder-target='unsaved']", visible: :all)
    expect(page).to have_css("[data-website-builder-delete-confirm-value]", visible: :all)
    expect(page).to have_css("[data-website-builder-structure-locked-value='true']", visible: :all)
    expect(page).to have_css("[data-website-builder-expand-all-value]", visible: :all)
    expect(page).not_to have_button(I18n.t("website.admin.pages.edit.expand_all"))
    expect(page).not_to have_css("[data-website-builder-target='kit']")
    expect(page).not_to have_button(I18n.t("website.admin.pages.edit.add_section"))
  end

  it "renders without a preview iframe when preview_url is omitted" do
    render_composer
    expect(page).not_to have_css("iframe")
    expect(page).not_to have_css("[data-website-builder-target='previewFrame']")
    expect(page).to have_text(I18n.t("website.admin.pages.edit.preview_label"))
  end

  it "uses shared warning badges for both workspace unsaved indicators" do
    render_composer

    expect(page).to have_css(".badge.badge-warning.hidden[data-website-builder-target='unsaved']",
      text: I18n.t("website.admin.pages.edit.unsaved"), count: 2, visible: :all)
  end

  it "renders the preview iframe when preview_url is passed" do
    render_composer(preview_url: "/81721200/admin/modules/website/pages/1/preview?embed=1")

    expect(page).to have_css("iframe[data-website-builder-target='previewFrame'][src*='embed=1']")
    expect(page).to have_css("iframe[title='#{I18n.t("website.admin.pages.edit.preview_label")}']")
    expect(page).to have_css("[data-website-builder-target='previewLoading'].hidden", visible: :all)
    expect(page).to have_css("[data-action*='website-builder#previewLoaded']", visible: :all)
    frame_classes = page.find('iframe')[:class].split
    expect(frame_classes).to include('h-full', 'w-full', 'flex-1', 'min-h-0')
    expect(frame_classes).not_to include('min-h-[22rem]', 'xl:min-h-[44rem]')
  end

  it "omits slug and locks home on the home page" do
    render_composer(page: page_for(home: true, slug: "", title: "Home"))

    expect(page).not_to have_css("[name='website_page[slug]']", visible: :all)
    expect(page).to have_field("website_page[home]", type: :checkbox, checked: true, disabled: true)
    expect(page).to have_field("website_page[home]", type: :hidden, with: "1")
    expect(page).to have_text(I18n.t("website.admin.pages.form.home_locked"))
  end

  it "offers a set-home checkbox for inner pages" do
    render_composer
    expect(page).to have_field("website_page[home]")
    expect(page).to have_css("[data-action*='website-builder#confirmSetHome']")
    expect(page).not_to have_text(I18n.t("website.admin.pages.form.home_locked"))
  end

  it "shows the empty sections state and kit templates when structure is unlocked" do
    render_composer(structure_locked: false)

    expect(page).to have_text(I18n.t("website.admin.pages.edit.no_sections_title"))
    expect(page).to have_button(I18n.t("website.admin.pages.edit.add_section"))
    Websites::SectionKit::TYPES.each do |type|
      expect(page).to have_css("template[data-section-template='#{type}']", visible: :all)
      expect(page).to have_css("[data-type='#{type}']", visible: :all)
    end
    Websites::SectionKit.groups.each_key do |group_key|
      expect(page).to have_text(I18n.t("website.sections.groups.#{group_key}"))
    end
  end

  it "renders existing sections including an unknown type" do
    render_composer(
      page: page_for(
        sections: [
          { "id" => "sec_a", "type" => "quote", "props" => { "quote" => "Hello" } },
          { "id" => "sec_b", "type" => "not_a_kit", "props" => {} }
        ]
      )
    )

    expect(page).to have_text(I18n.t("website.sections.quote.name"))
    expect(page).to have_text("Hello")
    expect(page).to have_text(I18n.t("website.admin.pages.edit.unknown_section"))
    expect(page).to have_css("[data-website-builder-target='empty'].hidden", visible: :all)
  end

  it "renders model errors above the identity fields" do
    record = WebsitePage.new(title: "About", slug: "about")
    record.errors.add(:slug, I18n.t("website.errors.slug_taken"))
    render_composer(page: record)

    expect(page).to have_text(I18n.t("website.errors.slug_taken"))
  end

  it "renders identity only without home, sections, or preview" do
    render_composer(identity_only: true)

    expect(page).to have_css("form#website-page-form [data-new-page-shell].max-w-xl")
    expect(page).not_to have_css("[data-controller='website-layout-picker']")
    expect(page).to have_button(I18n.t("website.admin.pages.new.submit"))
    expect(page).to have_field("website_page[title]", with: "About")
    expect(page).not_to have_css("[name='website_page[slug]']", visible: :all)
    expect(page).not_to have_field("website_page[home]")
    expect(page).not_to have_text(I18n.t("website.admin.pages.edit.sections"))
    expect(page).not_to have_button(I18n.t("website.admin.pages.edit.add_section"))
    expect(page).not_to have_button(I18n.t("website.admin.pages.edit.expand_all"))
    expect(page).not_to have_css("iframe")
    expect(page).not_to have_css("template[data-section-template]", visible: :all)
  end

  it "renders layout radios on identity-only when layouts are passed" do
    layout = build_stubbed(:website_layout, key: "article", name: "Article", description: "A long read")
    allow(layout).to receive(:display_name).and_return("Article")
    allow(layout).to receive(:display_description).and_return("A long read")
    allow(layout).to receive(:sections).and_return([ { "type" => "rich_text", "props" => {} } ])

    render_composer(identity_only: true, layouts: [ layout ])

    expect(page).to have_css("form#website-page-form > [data-new-page-shell][data-controller='website-layout-picker']")
    expect(page).to have_field("website_page[layout_key]", type: :radio, with: "article")
    expect(page).to have_text("Article")
  end

  it "shows the page's public path in the preview address bar" do
    render_composer(page: page_for(sections: [ { "id" => "sec_a", "type" => "quote", "props" => {} } ]),
                    preview_url: "/preview", public_path: "/81721200/site/about")

    expect(page).to have_css("[data-preview-address]", text: "/81721200/site/about")
  end

  it "falls back to the preview label in the address bar without a public path" do
    render_composer(page: page_for(sections: [ { "id" => "sec_a", "type" => "quote", "props" => {} } ]),
                    preview_url: "/preview")

    expect(page).to have_css("[data-preview-address]", text: I18n.t("website.admin.pages.edit.preview_address"))
  end

  it "shows a locked layout caption on the content editor" do
    render_composer(page: page_for(layout_key: "article", sections: [
      { "id" => "sec_a", "type" => "quote", "props" => { "quote" => "Hello" } }
    ]))

    expect(page).to have_text(I18n.t("website.admin.pages.form.layout_locked", name: I18n.t("website.layouts.article.name")))
    expect(page).to have_text(I18n.t("website.admin.pages.edit.sections"))
  end

  it "uses a split workspace and collapsed identity for a persisted page with preview" do
    record = build_stubbed(:website_page, title: "About", slug: "about", layout_key: "article", sections: [])
    render_composer(page: record, preview_url: "/81721200/admin/modules/website/pages/1/preview?embed=1")

    expect(page).to have_css("[data-website-workspace='true']")
    expect(page).to have_css("[data-identity-panel]", visible: :all)
    expect(page).to have_css("[data-website-builder-target='previewStage']")
    expect(page).to have_css("button[data-website-builder-target='viewportBtn'][data-viewport='desktop']")
    expect(page).to have_css("button[data-website-builder-target='viewportBtn'][data-viewport='tablet']")
    expect(page).to have_css("button[data-website-builder-target='viewportBtn'][data-viewport='mobile']")
    expect(page).to have_css("[data-action*='website-builder#persist']")
    expect(page).to have_css("iframe[data-draft-url]")
    expect(page).to have_text(I18n.t("website.admin.pages.edit.page_settings"))
    expect(page).to have_css("[data-website-builder-target='editorPane']")
    expect(page).to have_css("[data-website-builder-target='previewPane']")
    expect(page).not_to have_css("nav[class*='xl:w-52']")
    expect(page).to have_css("[data-workspace-outline]")
    expect(page).to have_css("[data-workspace-detail].hidden", visible: :all)
    expect(page).to have_css("[data-workspace-identity-nav]")
    expect(page).to have_css("[data-identity-panel].hidden", visible: :all)
    expect(page).to have_css("[data-website-builder-target='editorPane'][class*='xl:w-[28rem]'][class*='xl:max-w-[38%]']")
    expect(page).not_to have_css("[data-website-builder-target='editorPane'][class*='xl:flex-row']")
    expect(page).to have_css("[data-workspace-inspector].overflow-y-auto .max-w-3xl", visible: :all)
    expect(page).not_to have_css("details[data-identity-panel]")
    expect(page).to have_css("#website-page-identity-heading", text: I18n.t("website.admin.pages.edit.page_settings"), visible: :all)
    expect(page).to have_css("iframe.min-h-0.h-full.flex-1")
    expect(page).to have_button(I18n.t("website.admin.pages.edit.workspace_edit"))
    expect(page).to have_css("button[data-website-builder-target='paneBtn'][data-pane='preview']")
    expect(page).to have_css("[role='tablist'][aria-label='#{I18n.t("website.admin.pages.edit.workspace_panes")}']")
    %w[editor preview].each do |pane|
      selected = pane == "editor"
      expect(page).to have_css("#website-workspace-tab-#{pane}[role='tab'][aria-controls='website-workspace-panel-#{pane}'][aria-selected='#{selected}'][aria-pressed='#{selected}'][tabindex='#{selected ? 0 : -1}'][data-action*='keydown->website-builder#navigatePaneTabs']")
      expect(page).to have_css("#website-workspace-panel-#{pane}[role='tabpanel'][aria-labelledby='website-workspace-tab-#{pane}']")
      expect(page).not_to have_css("#website-workspace-panel-#{pane}[hidden], #website-workspace-panel-#{pane}[inert], #website-workspace-panel-#{pane}[aria-hidden]", visible: :all)
    end
  end

  it "renders a section navigator for jumping between blocks" do
    render_composer(
      page: page_for(sections: [
        { "id" => "sec_hero", "type" => "hero_cinematic", "props" => { "headline" => "Welcome" } },
        { "id" => "sec_quote", "type" => "quote", "props" => { "quote" => "Hello" } },
        { "id" => "sec_mystery", "type" => "not_a_kit", "props" => {} },
        { "id" => "", "type" => "quote", "props" => { "quote" => "Skip" } }
      ]),
      preview_url: "/preview"
    )

    expect(page).to have_css("nav[aria-label='#{I18n.t("website.admin.pages.edit.section_nav")}']")
    expect(page).to have_css("button[data-website-builder-target='sectionNav'][data-section-id='sec_hero']")
    expect(page).to have_css("button[data-website-builder-target='sectionNav'][data-section-id='sec_quote']")
    expect(page).to have_css("button[data-website-builder-target='sectionNav'][data-section-id='sec_mystery']")
    nav = page.find("[data-workspace-section-nav][role='tablist']")
    expect(nav[:class]).to include("flex-col")
    expect(nav[:class]).not_to include("overflow-x-auto")
    expect(nav).to have_text("Welcome")
    expect(nav).to have_text("Hello")
    expect(nav).to have_css("[data-section-id='sec_hero'] [data-section-preview]", text: "Welcome")
    expect(nav).to have_css("[data-section-id='sec_quote'] [data-section-preview]", text: "Hello")
    expect(nav.find("[data-section-id='sec_hero'] [data-section-preview]")[:class]).to include("truncate")
    expect(nav.find("#website-section-tab-sec_hero")[:class].split).to include("w-full", "aria-selected:bg-accent-subtle")
    %w[sec_hero sec_quote sec_mystery].each_with_index do |id, index|
      expect(nav).to have_css("#website-section-tab-#{id}[role='tab'][aria-controls='website-section-panel-#{id}'][aria-selected='#{index.zero?}'][aria-current='#{index.zero?}'][tabindex='#{index.zero? ? 0 : -1}'][data-action*='keydown->website-builder#navigateSectionTabs']")
      expect(nav).to have_css("[data-section-id='#{id}'] [data-section-number]", text: (index + 1).to_s)
      expect(nav).to have_css("[data-section-id='#{id}'] [data-section-label]")
      expect(page).to have_css("#website-section-panel-#{id}[role='tabpanel'][aria-labelledby='website-section-tab-#{id}'][data-section-label]", visible: :all)
    end
    expect(page).to have_text(I18n.t("website.admin.pages.edit.unknown_section"))
    expect(page).not_to have_css("button[data-section-id='']")
  end

  it "renders a writing rail without kit chrome in the workspace" do
    render_composer(
      page: page_for(
        layout_key: "presence_about",
        sections: [
          { "id" => "sec_split", "type" => "split_image_text", "props" => { "heading" => "Studio", "image_url" => "https://cdn.example/a.jpg" } },
          { "id" => "sec_quote", "type" => "quote", "props" => { "quote" => "Hello" } }
        ]
      ),
      preview_url: "/preview",
      upload_url: "/81721200/admin/modules/website/media"
    )

    expect(page).to have_css("[data-workspace-rail]")
    expect(page).to have_css("[data-website-builder-upload-url-value]", visible: :all)
    expect(page).to have_css("[data-image-replace]", text: I18n.t("website.admin.pages.form.replace_photo"), visible: :all)
    expect(page).to have_css("summary", text: I18n.t("website.admin.pages.form.edit_image_link"), visible: :all)
    expect(page).not_to have_css("[data-field-section] > h3, [data-field-section] > h4", visible: :all)
    expect(page).not_to have_button(I18n.t("website.admin.pages.edit.expand_all"))
    expect(page).to have_css("[data-section-type='quote'].hidden", visible: :all)
    expect(page).to have_css("[data-section-type='split_image_text'].hidden", visible: :all)
    expect(page).to have_css("button[data-website-builder-target='sectionNav'][data-section-id='sec_split']")
  end

  it "numbers each locked workspace section and links it to its neighbours" do
    render_composer(
      page: page_for(sections: [
        { "id" => "sec_split", "type" => "split_image_text", "props" => { "heading" => "Studio" } },
        { "id" => "sec_quote", "type" => "quote", "props" => { "quote" => "Hello" } }
      ]),
      preview_url: "/preview"
    )

    first = page.find("#website-section-panel-sec_split", visible: :all)
    second = page.find("#website-section-panel-sec_quote", visible: :all)
    expect(first).to have_css("[data-section-position]", text: I18n.t("website.admin.pages.edit.section_position", number: 1, total: 2), visible: :all)
    expect(first).not_to have_css("[data-section-step='previous']", visible: :all)
    expect(first).to have_css("[data-section-step='next'][data-section-id='sec_quote']", text: I18n.t("website.sections.quote.name"), visible: :all)
    expect(second).to have_css("[data-section-position]", text: I18n.t("website.admin.pages.edit.section_position", number: 2, total: 2), visible: :all)
    expect(second).to have_css("[data-section-step='previous'][data-section-id='sec_split']", visible: :all)
    expect(second).not_to have_css("[data-section-step='next']", visible: :all)
  end

  it "leaves step navigation out of an unlocked workspace" do
    render_composer(
      page: page_for(sections: [
        { "id" => "sec_a", "type" => "quote", "props" => { "quote" => "A" } },
        { "id" => "sec_b", "type" => "quote", "props" => { "quote" => "B" } }
      ]),
      preview_url: "/preview",
      structure_locked: false
    )

    expect(page).not_to have_css("[data-section-position]", visible: :all)
    expect(page).not_to have_css("[data-section-steps]", visible: :all)
  end

  it "keeps the kit outside the scrolling tablist and provides an inert dynamic tab template" do
    render_composer(structure_locked: false)

    outline = page.find("[data-workspace-outline]")
    expect(outline).to have_css("[data-workspace-section-nav]")
    expect(outline).to have_css("#website-kit-picker", visible: :all)
    expect(outline).not_to have_css("[data-workspace-section-nav] #website-kit-picker", visible: :all)
    expect(page.find("[data-website-builder-target='editorPane']")[:class]).not_to include("overflow-hidden")
    template = rendered_content.match(/<template data-section-nav-template>(.*?)<\/template>/m)[1]
    button = Nokogiri::HTML.fragment(template).at_css("button")
    expect(button["id"]).to eq("website-section-tab-SECTION_ID")
    expect(button["aria-controls"]).to eq("website-section-panel-SECTION_ID")
    expect(button["role"]).to eq("tab")
    expect(button["aria-selected"]).to eq("false")
    expect(button["tabindex"]).to eq("-1")
    expect(button.at_css("[data-section-label]").text).to be_empty
    expect(button.at_css("[data-section-preview]").text).to be_empty
    expect(button.at_css("[data-section-preview]")["class"]).to include("hidden")
  end

  it "preserves the embedded nonworkspace composition" do
    render_composer(embedded: true, structure_locked: false, page: page_for(sections: [
      { "id" => "sec_quote", "type" => "quote", "props" => { "quote" => "Hello" } }
    ]))

    expect(page).to have_css("section.card details[open]")
    expect(page).to have_css("nav button", text: "Hello")
    expect(page).not_to have_css("[data-workspace-section-nav], [data-workspace-inspector], [role='tabpanel']")
    expect(page).to have_css("template[data-section-template]", visible: :all)
  end

  %w[en zh-CN].each do |locale|
    it "supplies localized content-control templates and retains reset confirmation in #{locale}" do
      I18n.with_locale(locale) do
        render_composer
        host = page.find('[data-controller="website-builder"]')
        %w[item_label_format item_action_format array_limit_format image_load_failed].each do |key|
          expect(host["data-website-builder-#{key.tr('_', '-')}-value"]).to eq(I18n.t("website.admin.pages.form.#{key}"))
        end
        expect(JSON.parse(host['data-website-builder-item-actions-value'])).to eq(
          'up' => I18n.t('website.admin.pages.index.move_up'), 'down' => I18n.t('website.admin.pages.index.move_down'),
          'duplicate' => I18n.t('website.admin.pages.edit.duplicate_item'), 'remove' => I18n.t('common.actions.remove')
        )
        expect(host['data-website-builder-reset-confirm-value']).to eq(I18n.t('website.admin.pages.edit.reset_section_confirm'))
      end
    end
  end
end
