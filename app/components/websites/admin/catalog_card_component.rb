# frozen_string_literal: true

module Websites
  module Admin
    # Marketplace-style catalog card: live thumbnail, hover overlay, meta slot.
    class CatalogCardComponent < ApplicationComponent
      renders_one :thumbnail

      def initialize(key:, kind:, edit_path: nil, preview_path: nil, lazy: false, category: nil, family: nil)
        @key = key.to_s
        @kind = kind.to_sym
        @edit_path = edit_path
        @preview_path = preview_path
        @lazy = lazy
        @category = category
        @family = family
      end

      attr_reader :key, :kind, :edit_path, :preview_path, :category, :family

      def overlay?
        edit_path.present? || preview_path.present?
      end

      def lazy?
        @lazy
      end

      def article_data
        data = {
          catalog_card: true,
          catalog_kind: kind
        }
        data[:skeleton_key] = key if kind == :skeleton
        data[:layout_key] = key if kind == :layout
        data[:category] = category if category.present?
        data[:family] = family if family.present?
        data
      end

      def article_class
        classes = [
          "group relative flex h-full flex-col overflow-hidden rounded-2xl bg-surface",
          "ring-1 ring-border-subtle shadow-xs",
          "transition duration-150 ease-out",
          "hover:-translate-y-px hover:shadow-md hover:ring-border",
          "focus-within:-translate-y-px focus-within:shadow-md focus-within:ring-accent"
        ]
        classes << "[content-visibility:auto] [contain-intrinsic-size:auto_420px]" if lazy?
        classes.join(" ")
      end
    end
  end
end
