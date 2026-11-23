# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Websites::Admin::LinkFieldComponent, type: :component do
  def render_link(value: 'about', workspace: true, pages: [{ title: 'About', slug: 'about' }])
    render_inline(described_class.new(key: 'href', value: value, field_id: 'card_link', label: 'Link', site_pages: pages, workspace: workspace))
  end

  it 'keeps one canonical input and an associated hidden, keyboard-dismissable picker' do
    render_link
    expect(page).to have_css('[data-prop]', count: 1)
    expect(page).to have_css("input#card_link[data-prop='href'][value='about'][aria-describedby='card_link_status']")
    expect(page).to have_css("[data-href-toggle][aria-controls='card_link_picker_panel'][aria-expanded='false'][data-action='click->website-builder#toggleHrefPicker']")
    expect(page).to have_css("#card_link_picker_panel[data-href-picker].hidden[data-action='keydown.esc->website-builder#closeHrefPicker']", visible: :all)
    expect(page).to have_css("#card_link_picker_panel select[data-action='change->website-builder#applyHref'] option[value='about'][selected]", visible: :all)
    expect(page.find("option[value='about']", visible: :all).text).to eq('About')
    expect(page).to have_css('#card_link_status[data-href-status][role="status"]', visible: :all)
    expect(page).not_to have_text(I18n.t('website.admin.pages.form.href_hint'))
  end

  it 'reveals the page picker toggle on hover or focus and keeps it shown while open' do
    render_link
    expect(page.find('[data-href-field]')[:class].split).to include('group/link')
    expect(page.find('[data-href-toggle]')[:class].split).to include('pointer-fine:opacity-0', 'group-hover/link:opacity-100', 'group-focus-within/link:opacity-100', 'aria-expanded:opacity-100')
  end

  it 'preserves an unknown slug or external destination instead of choosing a different page' do
    %w[archived-page https://example.org/work].each do |value|
      render_link(value: value)
      expect(page).to have_css("input[data-prop='href'][value='#{value}']")
      expect(page).not_to have_css('option[selected]', visible: :all)
    end
  end

  it 'supports direct entry without any picker when the site has no pages' do
    render_link(pages: [])
    expect(page).to have_css('input[data-prop="href"]')
    expect(page).not_to have_css('[data-href-toggle], [data-href-picker], select', visible: :all)
  end

  it 'retains the static nonworkspace picker and hint' do
    render_link(workspace: false)
    expect(page).to have_select(I18n.t('website.admin.pages.form.href_picker'))
    expect(page).to have_text(I18n.t('website.admin.pages.form.href_hint'))
    expect(page).to have_css('input.studio-field')
    expect(page).not_to have_css('[data-href-toggle], [data-href-picker]', visible: :all)
  end

  it 'places a standalone workspace link label alongside its destination and aligns auxiliary controls below it' do
    render_link
    expect(page.find('[data-href-field]')[:class].split).to include('grid', 'grid-cols-[auto_minmax(0,1fr)]')
    expect(page).to have_css('label[for="card_link"]', text: 'Link')
    expect(page).to have_css('[data-href-picker].col-start-2', visible: :all)
    expect(page).to have_css('[data-href-status].col-start-2', visible: :all)
    render_inline(described_class.new(key: 'primary_href', value: '', field_id: 'primary', label: 'Destination', workspace: true))
    expect(page.find('[data-href-field]')[:class].split).to include('flex', 'flex-col')
  end
end
