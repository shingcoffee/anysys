# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Activities::ImportMedia do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }

  def source_blob(content_type: "image/png", customer_id: nil, filename: "shop.png")
    ActiveStorage::Blob.create_and_upload!(
      io: File.open(Rails.root.join("spec/fixtures/files/test.png")),
      filename: filename,
      content_type: content_type,
      identify: false
    ).tap { |blob| blob.update!(customer_id: customer_id) }
  end

  it "publishes a small photo enlarged, leaving the chat attachment as uploaded" do
    photo = ChunkyPNG::Image.new(30, 10, ChunkyPNG::Color.rgb(40, 120, 200)).to_blob
    source = Current.set(customer: customer) do
      ActiveStorage::Blob.create_and_upload!(io: StringIO.new(photo), filename: "pet.png", content_type: "image/png")
    end
    expect(source.service.exist?(source.key)).to be(true)

    copy = described_class.call(customer: customer, blob: source).blob

    expect(copy.metadata).to include("width" => 120, "height" => 40, "assistant_source_blob_id" => source.id)
    expect(MiniMagick::Image.read(copy.download).dimensions).to eq([120, 40])
    expect(source.download).to eq(photo)
  end

  it "copies the bytes into a new tenant blob and returns its site-media path" do
    source = source_blob

    result = described_class.call(customer: customer, blob: source)

    expect(result.success?).to be(true)
    expect(result.url).to match(%r{\A/#{customer.id}/site/media/[^/]+\z})
    copy = ActiveStorage::Blob.find_signed(result.url.split("/").last)
    expect(copy.id).not_to eq(source.id)
    expect(copy.customer_id).to eq(customer.id)
    expect(copy.download).to eq(source.download)
    expect(copy.filename.to_s).to eq("shop.png")
    expect(copy.metadata).to include("website_media" => true, "assistant_source_blob_id" => source.id)
  end

  it "stamps the copy with the target customer even when Current names another tenant" do
    source = source_blob

    result = Current.set(customer: other_customer) { described_class.call(customer: customer, blob: source) }

    expect(ActiveStorage::Blob.find_signed(result.url.split("/").last).customer_id).to eq(customer.id)
  end

  it "reuses an earlier import of the same source blob" do
    source = source_blob
    first = described_class.call(customer: customer, blob: source)

    expect {
      second = described_class.call(customer: customer, blob: source)
      expect(second.url).to eq(first.url)
      expect(second).to have_attributes(blob: first.blob, created: false)
    }.not_to change(ActiveStorage::Blob, :count)
    expect(first.created).to be(true)
  end

  describe ".placed_source_ids" do
    it "names the sources whose import is among the given urls, never another tenant's imports" do
      placed = source_blob
      removed = source_blob
      theirs = source_blob
      urls = [
        described_class.call(customer: customer, blob: placed).url,
        described_class.call(customer: other_customer, blob: theirs).url
      ].to_set
      described_class.call(customer: customer, blob: removed)

      ids = described_class.placed_source_ids(customer: customer, blob_ids: [placed.id, removed.id, theirs.id], urls: urls)

      expect(ids).to eq(Set[placed.id])
    end

    it "is empty for no blobs or no urls" do
      source = source_blob
      url = described_class.call(customer: customer, blob: source).url

      expect(described_class.placed_source_ids(customer: customer, blob_ids: [], urls: Set[url])).to be_empty
      expect(described_class.placed_source_ids(customer: customer, blob_ids: [source.id], urls: Set.new)).to be_empty
    end
  end

  it "imports a source blob stamped with the same customer" do
    expect(described_class.call(customer: customer, blob: source_blob(customer_id: customer.id)).success?).to be(true)
  end

  it "refuses a source blob that belongs to another tenant" do
    source = source_blob(customer_id: other_customer.id)

    result = nil
    expect {
      result = described_class.call(customer: customer, blob: source)
    }.not_to change(ActiveStorage::Blob, :count)

    expect(result.success?).to be(false)
    expect(result.error).to eq(I18n.t("website.errors.image_upload_failed"))
  end

  it "refuses a type website media does not accept" do
    result = described_class.call(customer: customer, blob: source_blob(content_type: "image/heic", filename: "a.heic"))

    expect(result.success?).to be(false)
    expect(result.error).to eq(I18n.t("website.errors.image_type"))
  end

  it "refuses a blob over the website media size limit" do
    source = source_blob
    source.update_column(:byte_size, Websites::Activities::UploadMedia::MAX_BYTES + 1)

    result = described_class.call(customer: customer, blob: source)

    expect(result.success?).to be(false)
    expect(result.error).to eq(I18n.t("website.errors.image_too_large"))
  end

  it "refuses a missing blob" do
    result = described_class.call(customer: customer, blob: nil)

    expect(result.success?).to be(false)
    expect(result.error).to eq(I18n.t("website.errors.image_missing"))
  end

  it "fails cleanly when the source bytes are gone from storage" do
    source = source_blob
    source.service.delete(source.key)

    result = described_class.call(customer: customer, blob: source)

    expect(result.success?).to be(false)
    expect(result.error).to eq(I18n.t("website.errors.image_upload_failed"))
  end

  it "refuses stored HTML disguised by an image MIME and filename without publishing a copy" do
    source = Current.set(customer: customer) do
      ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("<!DOCTYPE html><html><script>alert(1)</script></html>"),
        filename: "photo.png", content_type: "image/png", identify: false
      )
    end
    expect(source.service.exist?(source.key)).to be(true)
    result = nil

    expect { result = described_class.call(customer: customer, blob: source) }.not_to change(ActiveStorage::Blob, :count)
    expect(result).not_to be_success
    expect(result.error).to eq(I18n.t("website.errors.image_type"))
    expect(source.reload.metadata).not_to have_key("website_media")
  end

  it "classifies a correctly stamped source even when the invoking context names another tenant" do
    source = Current.set(customer: customer) do
      ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("<!DOCTYPE html><html>Not an image</html>"),
        filename: "photo.png", content_type: "image/png", identify: false
      )
    end

    result = Current.set(customer: other_customer) { described_class.call(customer: customer, blob: source) }

    expect(result).not_to be_success
    expect(result.error).to eq(I18n.t("website.errors.image_type"))
    expect(source.service.exist?(source.key)).to be(true)
  end

  describe ".imports_for" do
    it "is scoped to the importing customer" do
      source = source_blob
      described_class.call(customer: customer, blob: source)

      expect(described_class.imports_for(customer: customer, blob: source)).to exist
      expect(described_class.imports_for(customer: other_customer, blob: source)).not_to exist
      expect(described_class.imports_for(customer: customer, blob: source_blob)).not_to exist
    end
  end
end
