# frozen_string_literal: true

module AiAssistant
  # Accessible enlarged viewer for the current saved page render.
  class ArtifactPreviewDialogComponent < ApplicationComponent
    attr_reader :name, :frame_url, :preview_url, :details_url, :details_label, :subtitle

    # `frame_url` is the chrome-less render shown inside the dialog iframe;
    # `preview_url` is the standalone preview opened in a new tab.
    def initialize(name:, preview_url:, details_url:, details_label:, subtitle:, frame_url: nil)
      @name = name
      @frame_url = frame_url.presence || preview_url
      @preview_url = preview_url
      @details_url = details_url
      @details_label = details_label
      @subtitle = subtitle
    end

    def title_id
      "ai-assistant-artifact-preview-title"
    end
  end
end
