# frozen_string_literal: true

module Websites
  module Admin
    # The URL stays canonical, including while its auxiliary editor is closed.
    class MediaFieldComponent < ApplicationComponent
      REVEAL_CLASS = "transition pointer-fine:opacity-0 group-hover/media:opacity-100 group-focus-within/media:opacity-100"

      attr_reader :key, :value, :field_id, :label

      def initialize(key:, value:, field_id:, label:, uploadable: false, workspace: false)
        @key, @value, @field_id, @label = key, value.to_s, field_id, label
        @uploadable, @workspace = uploadable, workspace
      end

      def workspace?
        @workspace
      end

      def uploadable?
        @uploadable
      end

      def previewable?
        Websites::Href.media?(value)
      end

      def image_present?
        workspace? ? value.present? : previewable?
      end

      # Secondary photo actions (remove, edit link) wait for a mouse hover or focus.
      def reveal_class
        REVEAL_CLASS
      end
    end
  end
end
