# frozen_string_literal: true

module Websites
  module Activities
    class Provision
      Result = Struct.new(:success?, :model, :errors, keyword_init: true)

      def self.call(customer:)
        # Existing sites need no catalog refresh; recheck first-time creation
        # below under the same customer boundary used by every slug writer.
        existing = Website.for_customer(customer.id).first
        return Result.new(success?: true, model: existing, errors: []) if existing

        Websites::Catalog.sync!
        site = nil
        PageShortcuts::Collisions.with_customer_lock(customer_id: customer.id) do
          existing = Website.for_customer(customer.id).first
          return Result.new(success?: true, model: existing, errors: []) if existing

          site = Website.create!(
            customer_id: customer.id,
            name: customer.name,
            skeleton_key: default_skeleton_key,
            default_layout_key: default_layout_key_for(default_skeleton_key),
            theme: Websites::Theme.for_catalog(default_skeleton_key).to_stored,
            seo: {},
            footer: {},
            published: false
          )
          Websites::Skeletons.apply!(site, site.skeleton_key)
        end
        Result.new(success?: true, model: site, errors: [])
      rescue ActiveRecord::RecordInvalid => e
        Result.new(success?: false, model: site, errors: e.record.errors.full_messages)
      rescue ActiveRecord::RecordNotUnique
        Result.new(success?: false, model: site, errors: [I18n.t("website.errors.slug_taken")])
      rescue ActiveRecord::RecordNotFound
        Result.new(success?: false, model: site, errors: [I18n.t("page_shortcuts.errors.invalid_customer")])
      end

      def self.default_skeleton_key
        persisted = FeatureModules::Module.find_by(key: "website")&.configuration_schema_json
        key = persisted.is_a?(Hash) ? persisted.dig("default_skeleton_key", "default") : nil
        key = FeatureModules::Website::Registration.configuration_schema.dig("default_skeleton_key", "default") if key.blank?
        key = "presence" if key.blank? || !Websites::Catalog.known_skeleton?(key)
        key.to_s
      end

      def self.default_layout_key_for(skeleton_key)
        home = Websites::Skeletons.pages_for(skeleton_key).find { |page| ActiveModel::Type::Boolean.new.cast(page.stringify_keys["home"]) }
        home.to_h.stringify_keys["layout_key"].presence
      end
      private_class_method :default_layout_key_for
    end
  end
end
