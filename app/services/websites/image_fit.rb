# frozen_string_literal: true

module Websites
  # How a photo attached in the AI assistant goes onto the website without
  # losing detail. The chat attachment is never touched. The website copy is
  # the uploaded file itself when its long edge already reaches
  # TARGET_LONG_EDGE; a smaller photo is enlarged uniformly (never cropped or
  # stretched) with image_processing, on the backend
  # config.active_storage.variant_processor names. Sections then show the
  # copy whole instead of cropping it to the frame (see #fitted?).
  module ImageFit
    TARGET_LONG_EDGE = 1920
    MAX_UPSCALE = 4
    # Below this an enlargement costs a re-encode for no visible gain.
    MIN_UPSCALE = 1.1
    QUALITY = 90
    # GIF stays as uploaded: resampling would drop its animation.
    FORMATS = { "image/jpeg" => "jpg", "image/png" => "png", "image/webp" => "webp" }.freeze
    # libvips sharpens resized images itself; ImageMagick has to be asked.
    SHARPEN = { mini_magick: { sharpen: { radius: 0, sigma: 0.8 } } }.freeze

    Rendition = Struct.new(:bytes, :width, :height, keyword_init: true)

    module_function

    # [width, height] to enlarge a photo of this size to, or nil to keep it.
    def enlarged_size(width, height)
      return nil unless width.to_i.positive? && height.to_i.positive?

      scale = [TARGET_LONG_EDGE.fdiv([width, height].max), MAX_UPSCALE].min
      return nil if scale < MIN_UPSCALE

      [(width * scale).round, (height * scale).round]
    end

    # The bytes to publish for `blob`. A photo the image library cannot read
    # is published as uploaded.
    def rendition(blob)
      blob.analyze unless Assistant::Uploads.dimensions(blob).first
      width, height = Assistant::Uploads.dimensions(blob)
      size = enlarged_size(width, height) if FORMATS.key?(blob.content_type)
      return Rendition.new(bytes: blob.download, width: width, height: height) unless size

      Rendition.new(bytes: enlarge(blob, size), width: size.first, height: size.last)
    rescue ActiveStorage::FileNotFoundError
      raise
    rescue StandardError => e
      Rails.logger.warn("[websites.image_fit] kept blob #{blob.id} as uploaded: #{e.class}: #{e.message}")
      Rendition.new(bytes: blob.download, width: width, height: height)
    end

    # Whether `url` is website media imported from an assistant chat, which
    # sections show whole rather than cropped.
    def fitted?(url)
      signed_id = url.to_s[%r{/site/media/([^/?#]+)\z}, 1]
      blob = signed_id && ActiveStorage::Blob.find_signed(signed_id)
      blob.present? && blob.metadata.key?(Activities::ImportMedia::SOURCE_KEY)
    end

    def enlarge(blob, size)
      blob.open do |file|
        output = processor.source(file)
                          .resize_to_fit(*size, **SHARPEN.fetch(ActiveStorage.variant_processor, {}))
                          .saver(quality: QUALITY)
                          .convert(FORMATS.fetch(blob.content_type))
                          .call
        begin
          output.read
        ensure
          output.close!
        end
      end
    end

    def processor
      ActiveStorage.variant_processor == :vips ? ImageProcessing::Vips : ImageProcessing::MiniMagick
    end
    private_class_method :enlarge, :processor
  end
end
