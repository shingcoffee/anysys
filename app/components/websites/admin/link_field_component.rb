# frozen_string_literal: true

module Websites
  module Admin
    # One authoritative destination, with an optional native page picker.
    class LinkFieldComponent < ApplicationComponent
      attr_reader :key, :value, :field_id, :label, :site_pages

      def initialize(key:, value:, field_id:, label:, site_pages: [], workspace: false)
        @key, @value, @field_id, @label = key, value.to_s, field_id, label
        @site_pages = Array(site_pages).map(&:stringify_keys)
        @workspace = workspace
      end

      def workspace?
        @workspace
      end

      def inline_label?
        workspace? && key == "href"
      end
    end
  end
end
