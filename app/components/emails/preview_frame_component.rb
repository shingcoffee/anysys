# frozen_string_literal: true

module Emails
  # Sandboxed iframe for author-facing email HTML (show + dedicated preview).
  class PreviewFrameComponent < ApplicationComponent
    attr_reader :srcdoc, :title, :empty_message, :min_height_class

    def initialize(srcdoc:, title:, empty_message: nil, min_height_class: "min-h-[420px]")
      @srcdoc = srcdoc.to_s
      @title = title
      @empty_message = empty_message
      @min_height_class = min_height_class
    end

    def present? = srcdoc.present?
  end
end
