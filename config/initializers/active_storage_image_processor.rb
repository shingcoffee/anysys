# frozen_string_literal: true

# Active Storage analyzes and transforms images with libvips by default. The
# Docker image ships libvips; hosts without it (Amazon Linux 2023 has no
# package) fall back to ImageMagick, so image width/height metadata and
# variants still work there.
Rails.application.config.active_storage.variant_processor =
  begin
    require "vips"
    :vips
  rescue LoadError
    :mini_magick
  end
