# frozen_string_literal: true

module Websites
  module Activities
    class ReplaceSkeleton
      Result = Struct.new(:success?, :model, :errors, keyword_init: true)

      def self.call(site:, skeleton_key:)
        key = skeleton_key.to_s
        unless Websites::Catalog.known_skeleton?(key)
          return Result.new(success?: false, model: site, errors: [ I18n.t("website.errors.unknown_skeleton") ])
        end

        # Code-defined starters can be selected before the platform catalogs
        # have been initialized; their layout references must exist to validate.
        Websites::Catalog.sync! unless WebsiteLayout.exists?

        PageShortcuts::Collisions.with_customer_lock(customer_id: site.customer_id) do
          Website.for_customer(site.customer_id).scoping(all_queries: true) { site.reload }
          pages = Websites::Skeletons.apply!(site, key, replace: true)
          layout_key = pages.find(&:home?).layout_key
          site.update!(
            skeleton_key: key,
            default_layout_key: layout_key,
            theme: Websites::Theme.for_catalog(key).to_stored
          )
        end
        Result.new(success?: true, model: site.reload, errors: [])
      rescue ActiveRecord::RecordInvalid => e
        Result.new(success?: false, model: site, errors: e.record.errors.full_messages)
      rescue ActiveRecord::RecordNotUnique
        Result.new(success?: false, model: site, errors: [I18n.t("website.errors.slug_taken")])
      rescue ActiveRecord::RecordNotFound
        Result.new(success?: false, model: site, errors: [I18n.t("page_shortcuts.errors.invalid_customer")])
      end
    end
  end
end
