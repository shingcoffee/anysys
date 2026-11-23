# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::ImageFit do
  def png(width, height)
    ChunkyPNG::Image.new(width, height, ChunkyPNG::Color.rgb(40, 120, 200)).to_blob
  end

  def blob_with(bytes, content_type: "image/png", metadata: {})
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(bytes), filename: "pet", content_type: content_type, metadata: metadata, identify: false
    )
  end

  def pixel_size(bytes)
    image = MiniMagick::Image.read(bytes)
    [image.width, image.height]
  end

  describe ".enlarged_size" do
    it "enlarges toward the target long edge, keeping the aspect, at most MAX_UPSCALE times" do
      expect(described_class.enlarged_size(1000, 500)).to eq([1920, 960])
      expect(described_class.enlarged_size(30, 10)).to eq([120, 40])
    end

    it "keeps a photo that is already large enough, or nearly so, and one of unknown size" do
      expect(described_class.enlarged_size(1920, 1080)).to be_nil
      expect(described_class.enlarged_size(1800, 900)).to be_nil
      expect(described_class.enlarged_size(nil, nil)).to be_nil
    end
  end

  describe ".rendition" do
    it "enlarges a small photo uniformly and leaves the source untouched" do
      source = blob_with(png(30, 10))

      rendition = described_class.rendition(source)

      expect(rendition).to have_attributes(width: 120, height: 40)
      expect(pixel_size(rendition.bytes)).to eq([120, 40])
      expect(rendition.bytes.b).to start_with("\x89PNG".b)
      expect(source.reload.download).to eq(png(30, 10))
      expect(source.metadata).to include("width" => 30, "height" => 10)
    end

    it "keeps a jpeg a jpeg" do
      image = MiniMagick::Image.read(png(40, 20))
      image.format("jpg")

      rendition = described_class.rendition(blob_with(image.to_blob, content_type: "image/jpeg"))

      expect(rendition.bytes.b).to start_with("\xFF\xD8".b)
      expect(pixel_size(rendition.bytes)).to eq([160, 80])
    end

    it "publishes a large photo, a gif, and an unreadable file as uploaded" do
      large = png(2000, 12)
      gif = Base64.decode64("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")

      expect(described_class.rendition(blob_with(large)).bytes).to eq(large)
      expect(described_class.rendition(blob_with(gif, content_type: "image/gif")).bytes).to eq(gif)
      expect(described_class.rendition(blob_with("not an image")).bytes).to eq("not an image")
    end

    it "publishes the upload as it is when the image library fails" do
      source = blob_with(png(30, 10))
      allow(described_class).to receive(:enlarge).and_raise(MiniMagick::Error, "boom")

      expect(described_class.rendition(source)).to have_attributes(bytes: png(30, 10), width: 30, height: 10)
    end
  end

  describe ".fitted?" do
    let(:customer) { create(:customer) }

    it "is true only for website media imported from an assistant chat" do
      imported = blob_with(png(30, 10), metadata: { Websites::Activities::ImportMedia::SOURCE_KEY => 4 })
      uploaded = blob_with(png(30, 10), metadata: { "website_media" => true })

      expect(described_class.fitted?("/#{customer.id}/site/media/#{imported.signed_id}")).to be(true)
      expect(described_class.fitted?("/#{customer.id}/site/media/#{uploaded.signed_id}")).to be(false)
      expect(described_class.fitted?("/#{customer.id}/site/media/not-signed")).to be(false)
      expect(described_class.fitted?("https://images.unsplash.com/photo-1")).to be(false)
    end
  end
end
