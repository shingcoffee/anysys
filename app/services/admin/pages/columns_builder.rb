# frozen_string_literal: true

module Admin
  module Pages
    # Sort/search metadata for ModuleEntriesResolver. Visual rendering lives in
    # OpsTableComponent (audience meter, status dot) — not AdminTable badges.
    class ColumnsBuilder
      def self.call = new.call

      def call
        [name_column, visibility_column, launched_column, updated_column]
      end

      private

      def name_column
        {
          key: :name,
          label: I18n.t("common.labels.name"),
          sortable: true,
          searchable: true
        }
      end

      def visibility_column
        {
          key: :visibility,
          label: I18n.t("common.labels.visibility"),
          sortable: true,
          searchable: false,
          cell: ->(p) {
            audiences = p.visible_audiences
            return I18n.t("common.labels.none") if audiences.empty?

            audiences.map { |a| I18n.t("common.visibility.#{a}") }.join(", ")
          }
        }
      end

      def launched_column
        {
          key: :launched,
          label: I18n.t("common.labels.status"),
          sortable: true,
          searchable: false,
          cell: ->(p) { p.launched? ? I18n.t("common.status.live") : I18n.t("common.status.draft") }
        }
      end

      def updated_column
        {
          key: :updated_at,
          label: I18n.t("common.labels.updated_at"),
          type: :datetime,
          sortable: true,
          searchable: false,
          relative: true
        }
      end
    end
  end
end
