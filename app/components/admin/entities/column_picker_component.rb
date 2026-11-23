# frozen_string_literal: true

module Admin
  module Entities
    # Dropdown form to choose which entity attribute columns appear on the entries index.
    # System columns (id / created_at / updated_at) are always shown and not submitted.
    class ColumnPickerComponent < ApplicationComponent
      SYSTEM_KEYS = Admin::Entities::ColumnsBuilder::SYSTEM_KEYS

      attr_reader :entity, :setting, :update_path

      def initialize(entity:, setting:, update_path:)
        @entity = entity
        @setting = setting
        @update_path = update_path
      end

      def system_choices
        SYSTEM_KEYS.map do |key|
          {
            key: key.to_s,
            label: I18n.t("admin_misc.entities.columns.#{key}"),
            locked: true,
            checked: true
          }
        end
      end

      def attribute_choices
        candidate_fields.map do |field|
          slug = field["name_slug"].to_s
          {
            key: slug,
            label: attribute_label(field, slug),
            locked: false,
            checked: attribute_checked?(slug)
          }
        end
      end

      def array_param_name
        "entity_index_setting[visible_column_keys][]"
      end

      # Total columns shown: locked system columns + the checked attribute columns.
      def selected_count
        system_choices.size + attribute_choices.count { |c| c[:checked] }
      end

      private

      def candidate_fields
        @candidate_fields ||= begin
          system = SYSTEM_KEYS.map(&:to_s)
          extra = entity.computed_fields + entity.calculated_fields
          (entity.input_fields + extra).select { |f|
            slug = f["name_slug"].to_s
            slug.present? && !system.include?(slug)
          }.uniq { |f| f["name_slug"].to_s }
        end
      end

      def candidate_slugs
        @candidate_slugs ||= candidate_fields.map { |f| f["name_slug"].to_s }
      end

      def attribute_label(field, slug)
        field["display_label"].presence || field["name"].presence || slug
      end

      def attribute_checked?(slug)
        preferred = setting.visible_column_keys
        if preferred.nil?
          default_slugs.include?(slug)
        else
          preferred.map(&:to_s).include?(slug)
        end
      end

      # Mirrors Admin::Entities::ColumnsBuilder#default_slugs: every stored
      # field. Computed and calculated fields stay unchecked until picked.
      def default_slugs
        candidate_fields
          .reject { |field| %w[Computed Calculated].include?(field["type"].to_s) }
          .map { |field| field["name_slug"].to_s }
      end
    end
  end
end
