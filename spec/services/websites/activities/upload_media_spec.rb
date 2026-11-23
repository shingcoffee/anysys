# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Activities::UploadMedia do
  let_it_be(:customer) { create(:customer) }
  let(:png) do
    Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
  end

  def uploaded(filename:, type:, bytes:, size: nil)
    file = Tempfile.new([File.basename(filename, ".*"), File.extname(filename)])
    file.binmode
    file.write(bytes)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, type).tap do |upload|
      allow(upload).to receive(:size).and_return(size) if size
    end
  end

  around do |example|
    Current.set(customer: customer) { example.run }
  end

  it "stores a jpeg-family image and returns a public site-media path" do
    result = described_class.call(customer: customer, file: uploaded(filename: "photo.png", type: "image/png", bytes: png))

    expect(result.success?).to be(true)
    expect(result.url).to match(%r{\A/#{customer.id}/site/media/})
    blob = ActiveStorage::Blob.order(:id).last
    expect(blob.customer_id).to eq(customer.id)
    expect(blob.content_type).to eq("image/png")
    expect(blob.download).to eq(png)
    expect(blob.metadata["website_media"]).to be(true)
  end

  it "rejects a missing file" do
    result = described_class.call(customer: customer, file: nil)
    expect(result.success?).to be(false)
    expect(result.error).to eq(I18n.t("website.errors.image_missing"))
  end

  it "rejects a non-image type" do
    result = described_class.call(
      customer: customer,
      file: uploaded(filename: "notes.txt", type: "text/plain", bytes: "nope")
    )
    expect(result.success?).to be(false)
    expect(result.error).to eq(I18n.t("website.errors.image_type"))
  end

  it "rejects a file over 8 MB" do
    result = described_class.call(
      customer: customer,
      file: uploaded(filename: "huge.png", type: "image/png", bytes: png, size: 9.megabytes)
    )
    expect(result.success?).to be(false)
    expect(result.error).to eq(I18n.t("website.errors.image_too_large"))
  end

  {
    "HTML" => "<!DOCTYPE html><html><script>alert(1)</script></html>",
    "SVG" => '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>',
    "unidentified bytes" => "not actually an image"
  }.each do |kind, bytes|
    it "rejects #{kind} falsely declared as PNG without creating a storage blob" do
      result = nil
      expect do
        result = described_class.call(customer: customer, file: uploaded(filename: "photo.png", type: "image/png", bytes: bytes))
      end.not_to change(ActiveStorage::Blob, :count)

      expect(result).not_to be_success
      expect(result.error).to eq(I18n.t("website.errors.image_type"))
    end
  end

  it "classifies actual image bytes independently of filename and client MIME" do
    result = described_class.call(customer: customer, file: uploaded(filename: "photo.html", type: "text/html", bytes: png))

    expect(result).to be_success
    blob = ActiveStorage::Blob.find_signed(result.url.split("/").last)
    expect(blob.content_type).to eq("image/png")
    expect(blob.download).to eq(png)
    expect(Websites::MediaPolicy.public_image?(blob, customer_id: customer.id)).to be(true)
  end

  it "forces the target tenant stamp even when Current names another tenant" do
    other = create(:customer)
    result = Current.set(customer: other) do
      described_class.call(customer: customer, file: uploaded(filename: "photo.png", type: "image/png", bytes: png))
    end

    expect(ActiveStorage::Blob.find_signed(result.url.split("/").last).customer_id).to eq(customer.id)
  end
end
