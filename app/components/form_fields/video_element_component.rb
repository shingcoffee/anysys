# frozen_string_literal: true

module FormFields
  class VideoElementComponent < BaseElementComponent
    ALIGNMENTS = {
      "left"   => "text-left",
      "center" => "text-center mx-auto",
      "right"  => "text-right ml-auto"
    }.freeze

    attr_reader :video_url, :alignment

    def initialize(video_url:, alignment: "center", theme: {})
      super(theme: theme)
      @video_url = video_url
      @alignment = alignment
    end

    def embed_url
      return nil if video_url.blank?

      if video_url.include?("youtube.com/watch")
        video_id = video_url[/[?&]v=([^&]+)/, 1]
        "https://www.youtube.com/embed/#{video_id}" if video_id
      elsif video_url.include?("youtu.be/")
        video_id = video_url[/youtu\.be\/([^?&]+)/, 1]
        "https://www.youtube.com/embed/#{video_id}" if video_id
      elsif video_url.include?("vimeo.com/")
        video_id = video_url[/vimeo\.com\/(\d+)/, 1]
        "https://player.vimeo.com/video/#{video_id}" if video_id
      end
    end

    def video_present?
      embed_url.present?
    end

    def video_alignment_class
      ALIGNMENTS[alignment] || ALIGNMENTS["center"]
    end
  end
end
