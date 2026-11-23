# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Admin::SectionEditorComponent, type: :component do
  def render_section(type:, props: {}, **opts)
    render_inline(
      described_class.new(
        section: { "id" => "sec_1", "type" => type, "props" => props },
        index: 0,
        expanded: true,
        **opts
      )
    )
  end

  it 'presents only the target top-level headline as a multiline control without changing shared schema or data controls' do
    site = Website.new(id: 7, customer_id: 81_721_200)
    record = WebsitePage.new(website_id: 7, customer_id: 81_721_200, slug: 'about')
    context = Websites::HomeSite::Presentation.for(website: site, page: record)
    original = Websites::SectionFields.schema_for('hero_centered').deep_dup
    [true, false].each do |workspace|
      render_section(type: 'hero_centered', workspace: workspace, presentation: context,
        props: { headline: "First\nSecond", eyebrow: 'Editable', primary_label: 'Start', primary_href: '/auth/sign_up', media_mode: 'none' })
      dom = Nokogiri::HTML.fragment(rendered_content)
      expect(dom.at_css('textarea[data-prop="headline"]').text).to eq("First\nSecond")
      expect(dom.at_css('input[data-prop="eyebrow"]')['value']).to eq('Editable')
      expect(dom.css('[data-prop]').map { |node| node['data-prop'] }.uniq).to match_array(Websites::SectionKit::STRING_PROPS.fetch('hero_centered'))
      expect(dom.css('[data-style-trigger], [data-style-panel]')).to be_empty
    end
    expect(Websites::SectionFields.schema_for('hero_centered')).to eq(original)
    expect(original.find { |field| field[:key] == 'headline' }[:kind]).to eq(:string)
    render_section(type: 'hero_centered', props: { headline: 'Other site' })
    expect(page).to have_css('input[data-prop="headline"][value="Other site"]', visible: :all)
    expect(page).not_to have_css('textarea[data-prop="headline"]', visible: :all)
  end

  it "renders handle, type label, fields, and move/delete actions for a known type" do
    render_section(type: "hero_split", props: { "headline" => "Infrastructure", "eyebrow" => "Product" })

    expect(page).to have_css("[data-website-builder-target='row'][data-section-type='hero_split']")
    expect(page).to have_css("[data-website-builder-target='handle'][aria-label='#{I18n.t("website.admin.pages.edit.drag")}']")
    expect(page).to have_text(I18n.t("website.sections.hero_split.name"))
    expect(page).to have_text("Infrastructure")
    expect(page).to have_css("input[data-prop='headline'][value='Infrastructure']")
    expect(page).to have_css("[data-action='click->website-builder#moveUp'][aria-label='#{I18n.t("website.admin.pages.index.move_up")}']")
    expect(page).to have_css("[data-action='click->website-builder#moveDown']")
    expect(page).to have_css("[data-action='click->website-builder#removeSection'][aria-label='#{I18n.t("common.actions.delete")}']")
  end

  it "disables move up on the first row and move down on the last" do
    render_section(type: "quote", first: true, last: true, props: { "quote" => "Said." })

    expect(page).to have_css("[data-action='click->website-builder#moveUp'][disabled]")
    expect(page).to have_css("[data-action='click->website-builder#moveDown'][disabled]")
  end

  it "renders a warning row for an unknown type without crashing" do
    render_section(type: "mystery")

    expect(page).to have_text(I18n.t("website.admin.pages.edit.unknown_section"))
    expect(page).to have_css("[data-section-type='mystery']")
    expect(page).to have_css("[data-action='click->website-builder#removeSection']")
    expect(page).not_to have_css("details")
  end

  it "renders proof strip items with min/max add and remove controls" do
    items = Array.new(4) { |i| { "label" => "L#{i}", "value" => "#{i}" } }
    render_section(type: "proof_strip", props: { "items" => items })

    expect(page).to have_css("[data-array='items'][data-min='4'][data-max='6']")
    expect(page).to have_css("[data-array-item]", count: 4)
    expect(page).to have_css("[data-action='click->website-builder#addItem']")
    expect(page).to have_css("[data-action='click->website-builder#removeItem'][disabled]", count: 4)
    expect(page).to have_css("template[data-item-template]", visible: :all)
  end

  it "renders selects for tone, span, and image side plus href hints" do
    render_section(type: "hero_cinematic", props: { "tone" => "dark", "primary_href" => "about" })
    expect(page).to have_css("input[type='radio'][data-prop='tone'][value='dark'][checked]")
    expect(page).to have_css("input[data-prop='primary_href'][placeholder='#{I18n.t("website.admin.pages.form.href_placeholder")}']")
    expect(page).to have_text(I18n.t("website.admin.pages.form.href_hint"))

    render_inline(
      described_class.new(
        section: { id: "sec_2", type: "bento_grid", props: { "cells" => [{ "span" => "hero", "title" => "A" }] } },
        expanded: true
      )
    )
    expect(page).to have_css("select[data-prop='span']")

    render_inline(
      described_class.new(
        section: { "id" => "sec_3", "type" => "split_image_text", "props" => { "image_side" => "right" } },
        expanded: true
      )
    )
    expect(page).to have_css("input[type='radio'][data-prop='image_side'][value='right'][checked]")
  end

  it "renders a rich-text hint and seeds empty proof items to the contract minimum" do
    render_section(type: "rich_text", props: { "body" => "Hello" })
    expect(page).to have_text(I18n.t("website.admin.pages.form.rich_text_hint"))

    render_section(type: "proof_strip", props: {})
    expect(page).to have_css("[data-array-item]", count: 4)
  end

  it "locks structure and groups content fields with page-link and media tools" do
    render_section(
      type: "hero_cinematic",
      structure_locked: true,
      site_pages: [ { "title" => "About", "slug" => "about" } ],
      defaults: { "headline" => "Hello from layout" },
      props: {
        "headline" => "Hello from layout",
        "primary_href" => "about",
        "image_url" => "https://cdn.example/hero.jpg"
      }
    )

    expect(page).not_to have_css("[data-website-builder-target='handle']")
    expect(page).not_to have_css("[data-action='click->website-builder#removeSection']")
    expect(page).to have_button(I18n.t("website.admin.pages.edit.reset_section"))
    expect(page).to have_text(I18n.t("website.admin.pages.form.groups.copy"))
    expect(page).to have_text(I18n.t("website.admin.pages.form.groups.links"))
    expect(page).to have_text(I18n.t("website.admin.pages.form.groups.media"))
    expect(page).to have_text(I18n.t("website.admin.pages.form.groups.options"))
    expect(page).to have_select(I18n.t("website.admin.pages.form.href_picker"))
    expect(page).to have_css("option[value='about'][selected]")
    expect(page).to have_css("img[data-image-preview][src='https://cdn.example/hero.jpg']")
    expect(page).to have_css("[data-char-count]", text: I18n.t("website.admin.pages.form.char_count", count: "Hello from layout".length))
    expect(page).to have_css("[data-section-defaults*='Hello from layout']")
  end

  it "renders a writing canvas without badges or group cards" do
    render_inline(
      described_class.new(
        section: {
          "id" => "sec_1",
          "type" => "split_image_text",
          "props" => { "heading" => "Studio", "image_url" => "https://cdn.example/a.jpg" }
        },
        expanded: true,
        structure_locked: true,
        workspace: true,
        uploadable: true
      )
    )

    expect(page).to have_css("h3", text: I18n.t("website.sections.split_image_text.name"))
    expect(page).not_to have_text(I18n.t("website.admin.pages.form.groups.copy"))
    expect(page).not_to have_css("[data-field-group]")
    expect(page).to have_css("[data-image-field] img[data-image-preview]")
    expect(page).to have_css("[data-image-replace]", text: I18n.t("website.admin.pages.form.replace_photo"), visible: :all)
    expect(page).to have_button(I18n.t("website.admin.pages.form.reset_content"))
    expect(page).to have_css("input[data-prop='image_url'][value='https://cdn.example/a.jpg']", visible: :all)
  end

  it "keeps primary actions, media and options direct with only the secondary action disclosed" do
    render_section(type: "hero_cinematic", workspace: true, structure_locked: true)

    expect(page).to have_css("#website-section-panel-sec_1[role='tabpanel'][aria-labelledby='website-section-tab-sec_1'][data-section-label='#{I18n.t("website.sections.hero_cinematic.name")}']")
    expect(page).to have_css("h3[title='#{I18n.t("website.sections.hero_cinematic.description")}']", text: I18n.t("website.sections.hero_cinematic.name"))
    expect(page).not_to have_text(I18n.t("website.sections.hero_cinematic.description"))
    expect(page).not_to have_css("[data-section-position]")
    expect(page).not_to have_css("[data-section-steps]")
    expect(page).to have_css("input.input-field[data-prop='headline'][value='']")
    expect(page).not_to have_text(I18n.t("website.admin.pages.form.groups.copy"))
    expect(page).not_to have_css("[data-field-group]")
    expect(page).to have_css("div[data-button-pair='primary'] fieldset input[data-prop='primary_label']")
    expect(page).to have_css("div[data-button-pair='primary'] fieldset input[data-prop='primary_href']")
    expect(page).to have_css("details[data-button-pair='secondary']:not([open]) > summary", exact_text: I18n.t("website.admin.pages.form.buttons.secondary"), normalize_ws: true)
    expect(page).to have_css("fieldset input[data-prop='tone']")
    expect(page).not_to have_css("details [data-image-field], details input[data-prop='tone']")
    expect(page).not_to have_css("header + p")
    expect(page).to have_css("button[data-action='click->website-builder#resetSection:prevent:stop'][aria-label='#{I18n.t("website.admin.pages.form.reset_content")}']")
  end

  it "shows the section position and previous/next steps in the locked workspace" do
    render_section(
      type: "hero_cinematic", workspace: true, structure_locked: true,
      step: { number: 2, total: 4, previous: { id: "sec_0", label: "Intro" }, next: { id: "sec_2", label: "Pricing" } }
    )

    expect(page).to have_css("[data-section-position]", text: I18n.t("website.admin.pages.edit.section_position", number: 2, total: 4))
    expect(page).to have_css("nav[data-section-steps][aria-label='#{I18n.t("website.admin.pages.edit.section_steps")}']")
    expect(page).to have_css(
      "button[data-section-step='previous'][data-section-id='sec_0'][data-action='click->website-builder#focusSection']",
      text: "#{I18n.t("website.admin.pages.edit.previous_section")} Intro", normalize_ws: true
    )
    expect(page).to have_css("button[data-section-step='next'][data-section-id='sec_2']", text: "Pricing")
  end

  it "omits the missing side of the step nav on the first and last sections" do
    render_section(type: "hero_cinematic", workspace: true, structure_locked: true,
                   step: { number: 1, total: 1, previous: nil, next: nil })

    expect(page).to have_css("[data-section-position]", text: I18n.t("website.admin.pages.edit.section_position", number: 1, total: 1))
    expect(page).not_to have_css("[data-section-steps]")

    render_section(type: "hero_cinematic", workspace: true, structure_locked: true,
                   step: { number: 3, total: 3, previous: { id: "sec_1", label: "Quote" }, next: nil })

    expect(page).to have_css("button[data-section-step='previous']")
    expect(page).not_to have_css("button[data-section-step='next']")
  end

  it "uses identifiable items and the same workspace controls in initial items and templates" do
    render_section(type: "card_grid", workspace: true, structure_locked: true, props: { "cards" => [{ "title" => "Card" }] })

    expect(page).to have_css("[data-array='cards'] details[data-array-item][open] > summary", text: "Card")
    expect(page).to have_css("[data-array-item] input.input-field[data-prop='title'][value='Card']")
    template = rendered_content.match(/<template data-item-template>(.*?)<\/template>/m)[1]
    expect(Nokogiri::HTML.fragment(template)).to have_css("input.input-field[data-prop='title']")
    expect(page).to have_css("[data-action='click->website-builder#duplicateItem']")
    expect(page).to have_css("[data-action='click->website-builder#moveItemUp']")
  end

  it "groups workspace fields into divided blocks without group headings" do
    render_section(type: "hero_cinematic", workspace: true, structure_locked: true)
    blocks = page.all("[data-field-section]", visible: :all)
    expect(blocks.map { |block| block["data-field-section"] }).to eq(%w[copy links media options])
    expect(page).not_to have_css("[data-field-section] > h3, [data-field-section] > h4", visible: :all)
    expect(page.find("[data-field-section='copy']").first(:xpath, "..")[:class].split).to include("divide-y")
    expect(page).not_to have_css("h3.text-heading, [data-button-pair].border-t")

    render_section(type: "card_grid", workspace: true, structure_locked: true)
    expect(page).to have_css("[data-field-section='copy']")
    expect(page).to have_css("[data-field-section='lists'] [data-array='cards']")
    expect(page).not_to have_css("[data-field-section] > h4", visible: :all)

    render_section(type: "quote", workspace: true, structure_locked: true)
    expect(page).to have_css("[data-field-section='copy']")
    expect(page).not_to have_css("[data-field-section='style']", visible: :all)
  end

  describe "Design panels beside each element" do
    def trigger_for(key)
      page.find("button[data-style-trigger][aria-controls='website-style-sec_1-#{key}']", visible: :all)
    end

    it "pins one uniform trigger to the label row of each text field, the first button label and each list" do
      render_section(type: "hero_split", workspace: true, structure_locked: true)

      field = page.find("[data-prop='headline']", visible: :all).first(:xpath, "..")
      expect(field).to have_css("[data-field-header] > div:last-child > button[data-style-trigger][aria-controls='website-style-sec_1-headline']", visible: :all)
      expect(field).to have_css("[data-style-panel]#website-style-sec_1-headline[hidden] [data-style-target='headline']", visible: :all)
      field_triggers = page.all("[data-field-header] button[data-style-trigger]", visible: :all)
      expect(field_triggers.map { |el| el[:class] }.uniq.size).to eq(1)
      expect(field_triggers.first[:class].split).to include("size-7", "pointer-fine:opacity-0", "group-hover/design:opacity-100")
      expect(field[:class].split).to include("group/design")
      header_trigger = page.find("header button[data-style-trigger]", visible: :all)[:class].split
      expect(header_trigger).to include("size-7")
      expect(header_trigger).not_to include("pointer-fine:opacity-0")

      buttons = page.find("[data-prop='primary_label']", visible: :all).first(:xpath, "..")
      expect(buttons).to have_css("[data-style-panel] [data-style-target='buttons']", visible: :all)
      expect(trigger_for("buttons")["aria-label"]).to eq(I18n.t("website.admin.pages.style.trigger", target: I18n.t("website.admin.pages.style.targets.buttons")))
      expect(page).not_to have_css("[data-prop='secondary_label'] ~ [data-style-panel]", visible: :all)
      expect(page).not_to have_css("[data-style-panel] [data-prop='primary_href']", visible: :all)

      render_section(type: "card_grid", workspace: true, structure_locked: true, props: { "cards" => [{ "title" => "Card" }] })
      list = page.find("[data-array='cards']", visible: :all)
      expect(list).to have_css("[data-field-header] button[data-add-item] + button[data-style-trigger][aria-controls='website-style-sec_1-cards']", visible: :all)
      expect(list[:class].split).to include("group/design")
      expect(list.all("[data-style-panel] details[data-style-target]", visible: :all).map { |el| el["data-style-target"] }).to start_with("cards", "cards.title")
      expect(page).not_to have_css("[data-array-item] [data-style-trigger], template [data-style-trigger]", visible: :all)
    end

    it "opens section design from the inspector header and folds the appearance selects into it" do
      render_section(type: "feature_grid", workspace: true, structure_locked: true, props: { "styles" => { "section" => { "scale" => "lg" } } })

      expect(page).not_to have_css("[data-section-design]", visible: :all)
      section_trigger = page.find("header button[data-style-trigger]", visible: :all)
      expect(section_trigger["aria-controls"]).to eq("website-style-sec_1-section")
      expect(section_trigger["data-edited"]).not_to be_nil
      expect(page).to have_css("header + [data-style-panel]#website-style-sec_1-section[hidden]", visible: :all)
      panel = page.find("[data-style-panel]#website-style-sec_1-section", visible: :all)
      expect(panel.all("[data-prop]", visible: :all).map { |el| el["data-prop"] }.uniq).to eq(%w[surface spacing align])
      expect(panel).to have_css("[data-style-target='section'] [data-style-prop='scale']", visible: :all)
      expect(page.all("[data-style-panel]", visible: :all).map { |el| el["id"] }.first).to eq("website-style-sec_1-section")
    end

    it "keeps the non-workspace section trigger in the summary" do
      render_section(type: "hero_split", expanded: true, structure_locked: true)

      expect(page).to have_css("summary button[data-style-trigger][aria-controls='website-style-sec_1-section']", visible: :all)
      expect(page).to have_css("summary button[data-action='click->website-builder#resetSection:prevent:stop']", visible: :all)
      expect(page).to have_css("[data-field-group] button[data-style-trigger][aria-controls='website-style-sec_1-headline']", visible: :all)
    end

    it "has no Design panels for unknown types or the marketing presentation" do
      render_section(type: "no_such_section", workspace: true)
      expect(page).not_to have_css("[data-style-trigger], [data-style-panel]", visible: :all)
    end
  end

  it "keeps the non-workspace composer in one card per group" do
    render_section(type: "hero_cinematic", expanded: true)

    expect(page.all("[data-field-group]", visible: :all).map { |card| card["data-field-group"] }).to eq(%w[copy links media options])
    expect(page).to have_css("[data-field-group='copy'] > h3", text: I18n.t("website.admin.pages.form.groups.copy"), visible: :all)
    expect(page).not_to have_css("[data-field-section]", visible: :all)
  end

  it "renders a list-only section directly without a redundant group heading" do
    render_section(type: "proof_strip", workspace: true, structure_locked: true)

    expect(page).to have_css("[data-array='items'] div[data-array-item]", count: 4)
    expect(page).not_to have_css("details[data-field-group], [data-field-group] h3")
  end

  it "lets locked list sections add, duplicate, and reorder items" do
    items = Array.new(4) { |i| { "label" => "L#{i}", "value" => "#{i}" } }
    render_section(type: "proof_strip", structure_locked: true, props: { "items" => items })

    expect(page).to have_text(I18n.t("website.admin.pages.form.groups.lists"))
    expect(page).to have_css("[data-action='click->website-builder#duplicateItem']")
    expect(page).to have_css("[data-action='click->website-builder#moveItemUp']")
    expect(page).to have_css("[data-action='click->website-builder#moveItemDown']")
    expect(page).to have_button(I18n.t("website.admin.pages.edit.add_item"))
  end

  Websites::SectionKit::TYPES.each do |type|
    it "renders fields for #{type}" do
      render_section(type: type)
      expect(page).to have_css("[data-section-type='#{type}']")
      name_key = "website.sections.#{type}.name"
      expect(page).to have_text(I18n.exists?(name_key) ? I18n.t(name_key) : type.humanize)
    end
  end

  %w[en zh-CN].each do |locale|
    Websites::SectionKit::TYPES.each do |type|
      it "renders every #{type} workspace prop and item template in #{locale}" do
        I18n.with_locale(locale) do
          # Independent catalog keys catch dropped or accidentally duplicated controls.
          array_key = Websites::SectionKit::ARRAY_PROPS[type]
          props = array_key ? { array_key => [{ "title" => "Title", "name" => "Name", "question" => "Question", "label" => "Label" }] } : {}
          render_section(type: type, props: props, workspace: true, structure_locked: true, uploadable: true)
          dom = Nokogiri::HTML.fragment(rendered_content)
          dom.css('template').each(&:remove)
          section_keys = dom.css('[data-prop]').reject { |node| node.ancestors.any? { |parent| parent.key?('data-array-item') } }.map { |node| node['data-prop'] }.uniq
          expect(section_keys - Websites::SectionKit::STYLE_KEYS).to match_array(Websites::SectionKit::STRING_PROPS.fetch(type, []))
          expect(section_keys & Websites::SectionKit::STYLE_KEYS).to match_array(
            Websites::SectionFields.style_fields(type).map { |field| field[:key] }
          )
          expect(dom.css('[data-field-group]')).to be_empty
          expect(rendered_content).not_to include('translation_missing', 'Translation missing')
          expect(dom.css('[id]').map { |node| node['id'] }.tally.values).to all(eq(1))
          if array_key
            expect(dom.at_css('[data-array]')['data-array']).to eq(array_key)
            expect(dom.css('[data-array-list] > [data-array-item]').size).to eq(1)
            expect(dom.css('[data-array-item] > summary button')).to be_empty
          end
        end
      end
    end
  end

  it "pairs quote attribution and contact details at the named content breakpoint" do
    { 'quote' => %w[attribution role], 'contact_info' => %w[email phone] }.each do |type, keys|
      render_section(type: type, workspace: true)
      dom = Nokogiri::HTML.fragment(rendered_content)
      pair = dom.at_css("[data-prop='#{keys.first}']").ancestors.find { |node| node['class'].to_s.include?('@min-[24rem]/content:grid-cols-2') }
      expect(pair.css('[data-prop]').map { |node| node['data-prop'] }).to eq(keys)
      expect(dom.css('[class]').any? { |node| node['class'].split.include?('@container/content') }).to be(true)
    end
  end

  it "keeps the CTA label and destination together and visible" do
    render_section(type: 'cta_band', workspace: true, props: { 'button_label' => 'Plan a visit', 'button_href' => 'contact' })
    expect(page).to have_css("[data-button-pair='button'] fieldset input[data-prop='button_label'][value='Plan a visit']")
    expect(page).to have_css("[data-button-pair='button'] fieldset input[data-prop='button_href'][value='contact']")
    expect(page).not_to have_css('[data-field-section] details')
    expect(page).to have_css("[data-button-pair='button'] legend", exact_text: I18n.t("comp_page_builder.component_palette.button"))
  end

  it "keeps the secondary summary accurate regardless of the saved button content" do
    render_section(type: 'hero_cinematic', workspace: true, props: { 'secondary_label' => 'Read more', 'secondary_href' => 'about' })
    expect(page).to have_css("details[data-button-pair='secondary'] > summary", exact_text: I18n.t("website.admin.pages.form.buttons.secondary"), normalize_ws: true)
    expect(page).to have_css("details[data-button-pair='secondary'] input[data-prop='secondary_label'][value='Read more']", visible: :all)
  end

  %w[en zh-CN].each do |locale|
    [true, false].each do |workspace|
      it "renders preview and pricing labels as copy in #{locale} with workspace #{workspace}" do
        I18n.with_locale(locale) do
          { "ai_preview" => %w[example_label prompt_label output_label], "pricing" => %w[featured_label] }.each do |type, keys|
            render_section(type: type, workspace: workspace, props: keys.index_with { |key| "Saved #{key}" })
            group = workspace ? "data-field-section" : "data-field-group"

            keys.each do |key|
              expect(page).to have_css("[#{group}='copy'] input[data-prop='#{key}'][value='Saved #{key}']")
              expect(page).to have_field(I18n.t(Websites::SectionFields::LABEL_KEYS.fetch(key)), with: "Saved #{key}")
            end
            expect(page).not_to have_css("[data-button-pair], [#{group}='links']")
            expect(rendered_content).not_to include("translation_missing", "Translation missing")
          end
        end
      end
    end
  end

  it "keeps an unpaired action label as a normal copy field" do
    component = described_class.new(section: { id: "sec_1", type: "hero_centered", props: { primary_label: "Start" } }, workspace: true)
    allow(component).to receive(:field_schema).and_return([Websites::SectionFields.string("primary_label")])
    render_inline(component)

    expect(page).to have_css("[data-field-section='copy'] input[data-prop='primary_label'][value='Start']")
    expect(page).not_to have_css("[data-button-pair]")
  end

  it "renders the hero media mode in options and preserves its selected value" do
    render_section(type: "hero_centered", workspace: true, props: { "media_mode" => "none" })

    expect(page).to have_css("[data-field-section='options'] select[data-prop='media_mode'] option[value='none'][selected]")
    expect(page).to have_select(I18n.t("website.admin.pages.form.fields.media_mode"), selected: I18n.t("website.admin.pages.form.media_modes.none"))
    expect(page).to have_css("[data-button-pair='primary'] input[data-prop='primary_href']")
  end
end
