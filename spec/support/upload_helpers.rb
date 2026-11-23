# frozen_string_literal: true

# Shared Rack upload builders. Fixture files instead of per-spec Tempfiles.
module UploadHelpers
  PNG_FIXTURE   = Rails.root.join("spec/fixtures/files/shot.png").freeze
  TXT_FIXTURE   = Rails.root.join("spec/fixtures/files/note.txt").freeze
  AUDIO_FIXTURE = Rails.root.join("spec/fixtures/files/clip.webm").freeze

  def png_upload(filename = "shot.png")
    Rack::Test::UploadedFile.new(PNG_FIXTURE, "image/png", original_filename: filename)
  end

  def txt_upload(filename = "note.txt")
    Rack::Test::UploadedFile.new(TXT_FIXTURE, "text/plain", original_filename: filename)
  end

  def audio_upload(filename = "clip.webm", content_type = "audio/webm")
    Rack::Test::UploadedFile.new(AUDIO_FIXTURE, content_type, original_filename: filename)
  end
end

RSpec.configure do |config|
  config.include UploadHelpers
end
