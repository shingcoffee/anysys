# frozen_string_literal: true

module Admin
  module Settings
    class MemberHubCardPresenter
      def initialize(source_class:, customer:)
        @source_class = source_class
        @customer     = customer
      end

      attr_reader :source_class, :customer

      def key          ; source_class.key.to_sym ; end
      def name         ; I18n.t("settings_people.sources.#{key}.name", default: source_class.name) ; end
      def description  ; I18n.t("settings_people.sources.#{key}.description", default: source_class.description) ; end
      def editable?    ; source_class.editable?   ; end

      def total_count
        effectives.size
      end

      def enabled_count
        effectives.count(&:enabled?)
      end

      def configure_path
        "/#{customer.id}/admin/settings/member/sources/#{key}"
      end

      private

      def effectives
        @effectives ||= ::Member::Surfaces.surfaces_in(source_key: key, customer: customer)
      end
    end
  end
end
