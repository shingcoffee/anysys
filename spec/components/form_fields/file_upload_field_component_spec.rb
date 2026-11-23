# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormFields::FileUploadFieldComponent, type: :component do
  def build_upload(**opts)
    described_class.new(field_name: :f, label: 'F', **opts)
  end

  it 'renders file input' do
    render_inline(described_class.new(field_name: :attachment, label: 'Upload File'))
    expect(page).to have_css('input[type="file"]')
  end

  it 'renders with accept attribute' do
    render_inline(described_class.new(field_name: :image, label: 'Image', accept: 'image/*'))
    expect(page).to have_css('input[accept="image/*"]')
  end

  it 'renders with multiple attribute' do
    render_inline(described_class.new(field_name: :files, label: 'Files', multiple: true))
    expect(page).to have_css('input[multiple]')
    expect(page).to have_css('input[name="files[]"]')
  end

  it 'lists the files an edited record holds and stops requiring a new one' do
    render_inline(build_upload(required: true, multiple: true, value: ['a.pdf', 'b.pdf']))

    expect(page).to have_text(I18n.t('comp_form_fields.file_upload.current_files', names: 'a.pdf, b.pdf'))
    expect(page).to have_text(I18n.t('comp_form_fields.file_upload.keep_current_hint'))
    expect(page).not_to have_css('input[required]')
  end

  it 'requires a file when none is stored yet' do
    render_inline(build_upload(required: true, value: []))

    expect(page).to have_css('input[required]')
    expect(page).not_to have_text(I18n.t('comp_form_fields.file_upload.keep_current_hint'))
  end

  it 'renders drag-drop zone' do
    render_inline(described_class.new(field_name: :attachment, label: 'Upload'))
    expect(page).to have_css('[data-file-drop-zone]')
  end

  describe '#max_size_label' do
    it 'returns nil when max_size is not set' do
      expect(build_upload.max_size_label).to be_nil
    end

    it 'formats sizes >= 1MB as MB label' do
      expect(build_upload(max_size: 5_000_000).max_size_label).to eq('5MB')
    end

    it 'formats sizes < 1MB as KB label' do
      expect(build_upload(max_size: 500_000).max_size_label).to eq('500KB')
    end

    it 'renders max size label in the template when max_size is set' do
      render_inline(build_upload(field_name: :doc, label: 'Document', max_size: 2_000_000))
      expect(page).to have_text('2MB')
    end
  end

  describe 'upload_cta_classes' do
    it 'returns a string containing a text- color class' do
      expect(build_upload.upload_cta_classes).to include('text-')
    end
  end

  describe "private field_type method (dead code — template renders input directly)" do
    it "returns :file" do
      expect(build_upload(field_name: :attachment, label: 'Upload').send(:field_type)).to eq(:file)
    end
  end
end
