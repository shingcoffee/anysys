# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Websites::Admin::MediaFieldComponent, type: :component do
  def render_media(value: '', workspace: true, uploadable: true)
    render_inline(described_class.new(key: 'image_url', value: value, field_id: 'card_photo', label: 'Photo', workspace: workspace, uploadable: uploadable))
  end

  it 'renders a compact empty state with upload and inline URL entry, without a remove action' do
    render_media
    expect(page).to have_css('[data-image-empty]:not(.hidden)', text: I18n.t('website.admin.pages.form.no_photo'))
    expect(page).to have_css('[data-image-add]:not(.hidden)')
    expect(page).to have_css('[data-image-clear].hidden', visible: :all)
    expect(page).to have_css('[data-image-present].hidden, [data-image-failed].hidden', count: 2, visible: :all)
    expect(page).to have_css('details:not([open]) input#card_photo[data-prop="image_url"]', visible: :all)
    expect(page).to have_css('[data-prop="image_url"]', count: 1, visible: :all)
    thumbnail = page.find('[data-image-preview]', visible: :all)
    expect(thumbnail.find(:xpath, '..')[:class].split).to include('h-16', 'w-20')
    expect(page).to have_css("[data-action*='dragover->website-builder#allowImageDrop'][data-action*='drop->website-builder#dropImage']")
    expect(page).to have_css('input[type="file"][aria-describedby~="card_photo_status"][aria-describedby~="card_photo_help"]', visible: :all)
  end

  it 'shows photo presence without exposing the remote URL in a summary' do
    value = 'https://cdn.example.org/photo.jpg?token=private'
    render_media(value: value)
    expect(page).to have_css('[data-image-preview][data-action="error->website-builder#imageError load->website-builder#imageLoaded"]')
    expect(page).to have_css('[data-image-present]:not(.hidden)', text: I18n.t('website.admin.pages.form.photo_added'))
    expect(page).to have_css('[data-image-replace]:not(.hidden), [data-image-clear]:not(.hidden)', count: 2)
    expect(page).to have_css('[data-image-empty].hidden', visible: :all)
    expect(page.find('summary').text).not_to include(value, 'token')
    expect(page).to have_css('#card_photo_status[data-image-status][role="status"][aria-live="polite"]', visible: :all)
    expect(page.find('#card_photo', visible: :all).value).to eq(value)
  end

  it 'distinguishes a malformed stored image from an empty field and keeps it editable' do
    render_media(value: 'not-an-image')
    expect(page).to have_css('[data-image-failed]:not(.hidden)', text: I18n.t('website.admin.pages.form.preview_unavailable'))
    expect(page).to have_css('[data-image-empty].hidden', visible: :all)
    expect(page).to have_css('[data-image-clear]:not(.hidden)')
    expect(page.find('#card_photo', visible: :all).value).to eq('not-an-image')
    expect(page).not_to have_css('[data-image-preview][src]', visible: :all)
  end

  it 'retains URL editing without upload support and accepts stored upload paths' do
    render_media(value: '/81721200/site/media/photo--id', uploadable: false)
    expect(page).to have_css('[data-image-preview][src="/81721200/site/media/photo--id"]')
    expect(page).to have_css('details input[data-prop="image_url"]', visible: :all)
    expect(page).not_to have_css('input[type="file"]', visible: :all)
  end

  it 'retains the large nonworkspace preview and existing URL disclosure wording' do
    render_media(value: 'https://cdn.example.org/photo.jpg', workspace: false)
    expect(page.find('[data-image-preview]')[:class].split).to include('aspect-[2/1]', 'w-full')
    expect(page).to have_css('summary', text: I18n.t('website.admin.pages.form.use_image_url'))
    expect(page).not_to have_css('[data-image-present], [data-image-failed]', visible: :all)
    expect(page).to have_css('label.form-label[for="card_photo"]')
    expect(page).to have_css('p.text-sm.text-text-tertiary', text: I18n.t('website.admin.pages.form.image_hint'), visible: :all)
  end

  it 'integrates workspace media controls beside the thumbnail and keeps format help accessible without repetition' do
    render_media(value: 'https://cdn.example.org/photo.jpg')
    field = page.find('[data-image-field]')
    expect(field.find('[data-action*="website-builder#dropImage"]')[:class].split).to include('grid', 'grid-cols-[5rem_minmax(0,1fr)]')
    expect(field.find('details')[:class].split).to include('col-start-2')
    summary = field.find('details > summary')
    expect(summary[:title]).to eq(I18n.t('website.admin.pages.form.edit_image_link'))
    expect(summary[:class].split).to include('absolute', 'right-0', 'top-0', 'size-8')
    expect(summary).to have_css('svg[aria-hidden="true"]')
    expect(summary).to have_css('span.a11y-clip', text: I18n.t('website.admin.pages.form.edit_image_link'), visible: :all)
    expect(field.find('[data-image-replace]', visible: :all).find(:xpath, '../../..')[:class].split).to include('pr-9')
    expect(field).to have_css('label.a11y-clip[for="card_photo"]', visible: :all)
    expect(field).to have_css('[data-image-present].a11y-clip', visible: :all)
    expect(field).to have_css('#card_photo_help.a11y-clip', text: I18n.t('website.admin.pages.form.image_hint'), visible: :all)
    expect(field).to have_css('input[data-prop="image_url"][aria-describedby~="card_photo_help"]', visible: :all)
    expect(field).not_to have_css('p.text-caption', text: I18n.t('website.admin.pages.form.image_hint'), visible: :all)
  end

  it 'keeps replace visible and reveals remove and the link editor on hover or focus' do
    render_media(value: 'https://cdn.example.org/photo.jpg')
    field = page.find('[data-image-field]')
    reveal = %w[pointer-fine:opacity-0 group-hover/media:opacity-100 group-focus-within/media:opacity-100]
    expect(field[:class].split).to include('group/media')
    expect(field.find('[data-image-clear]')[:class].split).to include(*reveal)
    expect(field.find('details > summary')[:class].split).to include(*reveal, 'group-open/url:opacity-100')
    expect(field.find('[data-image-replace]').find(:xpath, '..')[:class]).not_to include('opacity')

    render_media(value: 'https://cdn.example.org/photo.jpg', workspace: false)
    expect(page.find('[data-image-field]')[:class]).not_to include('group/media')
    expect(rendered_content).not_to include('pointer-fine:opacity-0')
  end
end
