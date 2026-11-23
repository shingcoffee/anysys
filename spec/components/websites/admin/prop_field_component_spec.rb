# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Admin::PropFieldComponent, type: :component do
  def render_field(key:, kind: :string, value: "", **opts)
    field = { key: key, kind: kind }
    field[:options] = opts.delete(:options) if opts.key?(:options)
    field[:hint] = opts.delete(:hint) if opts.key?(:hint)
    render_inline(
      described_class.new(
        field: field,
        value: value,
        field_id: "field_#{key}",
        site_pages: opts.delete(:site_pages) || [],
        option_label: opts.delete(:option_label),
        uploadable: opts.delete(:uploadable) || false,
        workspace: opts.delete(:workspace) || false,
        rows: opts.delete(:rows)
      )
    )
  end

  it "renders an href field with a site-page picker and custom option" do
    render_field(
      key: "primary_href",
      value: "about",
      site_pages: [ { title: "About", slug: "about" }, { "title" => "Team", "slug" => "team" } ]
    )

    expect(page).to have_css("[data-href-field] input[data-prop='primary_href'][value='about']")
    expect(page).to have_select(I18n.t("website.admin.pages.form.href_picker"))
    expect(page).to have_css("option[value='about'][selected]")
    expect(page).to have_css("[data-href-status].hidden", visible: :all)
    expect(page).to have_text(I18n.t("website.admin.pages.form.href_custom"))
  end

  it "leaves the page picker on custom when the href is not a site page" do
    render_field(key: "href", value: "https://example.com", site_pages: [ { "title" => "About", "slug" => "about" } ])

    expect(page).to have_css("input[data-prop='href'][value='https://example.com']")
    expect(page).not_to have_css("option[value='about'][selected]")
  end

  it "previews https images and shows the empty state otherwise" do
    render_field(key: "image_url", value: "https://cdn.example/a.jpg")
    expect(page).to have_css("[data-image-field] img[data-image-preview][src='https://cdn.example/a.jpg']")
    expect(page).to have_css("[data-image-empty].hidden", visible: :all)

    render_field(key: "image_url", value: "/12345678/site/media/abc--id")
    expect(page).to have_css("[data-image-field] img[data-image-preview][src='/12345678/site/media/abc--id']")

    render_field(key: "visual_url", value: "")
    expect(page).to have_css("[data-image-preview].hidden", visible: :all)
    expect(page).to have_text(I18n.t("website.admin.pages.form.image_empty"))
    expect(page).to have_button(I18n.t("website.admin.pages.form.clear_image"))
  end

  it "renders a photo dropzone and replace control when uploads are enabled" do
    render_field(key: "image_url", value: "https://cdn.example/a.jpg", uploadable: true)

    expect(page).to have_css("input[type='file'][accept*='image/jpeg']", visible: :all)
    expect(page).to have_text(I18n.t("website.admin.pages.form.replace_photo"))
    expect(page).to have_text(I18n.t("website.admin.pages.form.use_image_url"))
    expect(page).to have_css("[data-action*='website-builder#dropImage']")
  end

  it "counts characters on short copy and keeps body as a textarea" do
    render_field(key: "headline", value: "Hello")
    expect(page).to have_css("[data-count-field] [data-char-count]", text: I18n.t("website.admin.pages.form.char_count", count: 5))

    render_field(key: "body", kind: :textarea, value: "One\n\nTwo")
    expect(page.find("textarea[data-prop='body']").value).to eq("One\n\nTwo")
    expect(page).not_to have_css("[data-body-preview]", visible: :all)
  end

  it "reserves workspace counter space and reveals it only through its own named focus group" do
    render_field(key: "headline", workspace: true, value: "Hello")

    wrapper = page.find("[data-count-field]")
    counter = wrapper.find("[data-char-count]", visible: :all)
    expect(wrapper[:class].split).to include("group/prop-field")
    expect(wrapper).to have_css("input[data-prop='headline']")
    expect(wrapper).to have_css("[data-field-header] [data-char-count]", visible: :all)
    expect(counter[:class].split).to include("invisible", "group-focus-within/prop-field:visible")
    expect(counter[:class].split).not_to include("hidden", "group-focus-within:visible")
    expect(counter.text).to eq(I18n.t("website.admin.pages.form.char_count", count: 5))
  end

  it "keeps nonworkspace character counts visible without focus" do
    render_field(key: "headline", value: "Hello")

    expect(page.find("[data-count-field]")[:class]).not_to include("group/prop-field")
    expect(page.find("[data-char-count]")[:class].split).not_to include("invisible", "hidden", "group-focus-within/prop-field:visible")
  end

  it "renders email, phone, and segmented tone options" do
    render_field(key: "email", value: "hi@example.com")
    expect(page).to have_css("input[type='email'][data-prop='email']")

    render_field(key: "phone", value: "555")
    expect(page).to have_css("input[type='tel'][data-prop='phone']")

    render_field(
      key: "tone",
      kind: :select,
      value: "dark",
      options: %w[light dark],
      option_label: ->(option) { option == "dark" ? "Dark" : "Light" }
    )
    expect(page).to have_css("input[type='radio'][data-prop='tone'][value='dark'][checked]")
    expect(page).to have_text("Dark")
  end

  it "falls back to the raw option text and still shows a rich-text hint" do
    render_field(key: "span", kind: :select, value: "unit", options: %w[hero wide unit])
    expect(page).to have_css("option[value='unit']", text: "unit")

    render_field(key: "heading", kind: :textarea, hint: :rich_text, value: "Hi")
    expect(page).to have_text(I18n.t("website.admin.pages.form.rich_text_hint"))
    expect(page.find("p", text: I18n.t("website.admin.pages.form.rich_text_hint"))[:class].split).not_to include("hidden")
  end

  it "shows the workspace rich-text hint only while its own field has focus" do
    render_field(key: "heading", kind: :textarea, hint: :rich_text, value: "Hi", workspace: true)

    hint = page.find("p", text: I18n.t("website.admin.pages.form.rich_text_hint"), visible: :all)
    expect(hint[:class].split).to include("hidden", "group-focus-within/prop-field:block")
  end

  it "uses conventional labeled workspace writing controls without display typography" do
    %w[headline heading title body quote].each do |key|
      kind = %w[body quote].include?(key) ? :textarea : :string
      render_field(key: key, kind: kind, workspace: true, value: "Copy")

      control = page.find(".input-field[data-prop='#{key}']")
      expect(control[:class]).not_to match(/bg-transparent|text-\[1.75rem\]|text-lg|studio-field/)
      expect(page).to have_css("label[for='#{control[:id]}']", text: I18n.t(Websites::Admin::SectionEditorComponent::FIELD_LABEL_KEYS.fetch(key)))
    end
  end

  it "retains nonworkspace display typography" do
    render_field(key: "headline")
    expect(page).to have_css("input[class*='text-[1.75rem]'][class*='bg-transparent']")
  end

  it "associates workspace link and upload errors with their labeled controls" do
    render_field(key: "href", workspace: true)
    expect(page).to have_css("input#field_href[aria-describedby='field_href_status']")
    expect(page).to have_css("#field_href_status[data-href-status][role='status'][aria-live='polite']", text: I18n.t("website.errors.invalid_href"), visible: :all)

    render_field(key: "image_url", workspace: true, uploadable: true)
    expect(page).to have_css("input[type='file'][aria-describedby~='field_image_url_status'][aria-describedby~='field_image_url_help']", visible: :all)
    expect(page).to have_css("input#field_image_url[aria-describedby~='field_image_url_status'][aria-describedby~='field_image_url_help']", visible: :all)
    expect(page).to have_css("label[for='field_image_url']")
    expect(page).to have_css("#field_image_url_status[data-image-status][role='status'][aria-live='polite']", visible: :all)
  end

  it "sizes every workspace textarea for its editing context" do
    { 'subhead' => 2, 'body' => 3, 'quote' => 3, 'bio' => 3, 'answer' => 3, 'address' => 3 }.each do |key, rows|
      render_field(key: key, kind: :textarea, workspace: true)
      control = page.find('textarea')
      expect(control[:rows]).to eq(rows.to_s)
      expect(control[:class]).not_to include('min-h-[6rem]')
      expect(control[:class].split).to include('input-field', 'resize-y')
    end
    render_field(key: 'body', kind: :textarea, workspace: true, hint: :rich_text)
    expect(page).to have_css('textarea[rows="8"]')
  end

  it "uses intrinsic-width native radio fieldsets for all workspace choices" do
    { 'tone' => %w[light dark], 'image_side' => %w[left right], 'span' => %w[hero wide unit] }.each do |key, options|
      render_field(key: key, kind: :select, workspace: true, options: options, value: options.last)
      expect(page).to have_css("fieldset legend#field_#{key}_label")
      group = page.find('[role="radiogroup"]')
      expect(group[:class].split).to include('w-fit', 'max-w-full')
      expect(group[:class].split).not_to include('w-full', 'sm:w-auto')
      expect(group).to have_css("input[type='radio'][name='field_#{key}'][data-prop='#{key}']", count: options.size)
      expect(group).to have_css("input[value='#{options.last}'][checked]")
    end
  end

  it "accepts short workspace item copy without reducing rich-text or nonworkspace writing areas" do
    copy = "First line\nSecond line\nThird line"
    render_field(key: 'body', kind: :textarea, value: copy, workspace: true, rows: 2)
    expect(page.find('textarea').value).to eq(copy)
    expect(page).to have_css('textarea[rows="2"].resize-y')
    render_field(key: 'body', kind: :textarea, workspace: true, rows: 2, hint: :rich_text)
    expect(page).to have_css('textarea[rows="8"]')
    render_field(key: 'body', kind: :textarea, rows: 2)
    expect(page).to have_css('textarea[rows="8"]')
  end
end
