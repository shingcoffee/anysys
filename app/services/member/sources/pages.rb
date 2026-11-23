# frozen_string_literal: true

require_relative "builtin_surface"

module Member
  module Sources
    class Pages < Member::SurfaceSource
      def self.key         ; :pages ; end
      def self.name        ; I18n.t("admin_settings.member.sources.pages.name") ; end
      def self.description ; I18n.t("admin_settings.member.sources.pages.description") ; end
      def self.position    ; 30 ; end

      def surfaces
        action_winners(catalog.to_a).map { |page|
          BuiltinSurface.new(
            key: :"page_#{page.id}",
            label: page.name,
            icon: :document_text,
            path_seg: "pages/#{page.id}",
            default_enabled: false
          )
        }
      end

      def catalog
        ::Page.where(customer_id: [customer.id, nil]).launched.for_audience("member").order(:id)
      end

      # Same choice as ::Pages::ActionResolver.page_for, without a query per page:
      # one page per action key, a tenant page before a shared one.
      def action_winners(pages)
        keyed, unkeyed = pages.partition { |page| page.action_key.present? }
        winners = keyed.sort_by { |page| [page.customer_id ? 0 : 1, page.id] }.uniq(&:action_key)
        (unkeyed + winners).sort_by(&:id)
      end
      private :catalog, :action_winners

      register!
    end
  end
end
