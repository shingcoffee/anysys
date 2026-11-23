# frozen_string_literal: true

module Websites
  module Admin
    # Shared heading for catalog edit / new pages (layouts + skeletons).
    class CatalogEditorHeaderComponent < ApplicationComponent
      renders_one :actions

      def initialize(title:, description:, back_path:)
        @title = title
        @description = description
        @back_path = back_path
      end

      attr_reader :title, :description, :back_path
    end
  end
end
