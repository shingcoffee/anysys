# frozen_string_literal: true

module PageShortcuts
  module Activities
    class Save
      Result = Struct.new(:success?, :model, :errors, keyword_init: true)
      TARGET = /\A(WebsitePage|Page):([1-9][0-9]*)\z/

      class Workflow < Trailblazer::Activity::Railway
        step :scope_customer
        step :save_with_lock

        def scope_customer(ctx, shortcut:, customer_id:, **)
          shortcut.errors.clear
          cid = PathPolicy.customer_id(customer_id)
          allowed = cid && (shortcut.customer_id.nil? || shortcut.customer_id == cid)
          unless allowed
            shortcut.errors.add(:base, I18n.t("page_shortcuts.errors.invalid_customer"))
            return false
          end
          shortcut.customer_id = cid
          true
        end

        def save_with_lock(ctx, shortcut:, params:, **)
          Collisions.with_customer_lock(customer_id: shortcut.customer_id) do
            # Reform only syncs dirty properties. A stale model can otherwise
            # silently drop an explicitly submitted value equal to its old one.
            if shortcut.persisted?
              PageShortcut.for_customer(shortcut.customer_id).scoping(all_queries: true) { shortcut.reload }
            end
            validate(ctx, shortcut: shortcut, params: params) &&
              persist(ctx, shortcut: shortcut, contract: ctx[:contract])
          end
        rescue ActiveRecord::RecordNotFound
          shortcut.errors.add(:base, I18n.t("page_shortcuts.errors.invalid_customer"))
          false
        rescue ActiveRecord::RecordNotUnique
          shortcut.errors.add(:path, I18n.t("page_shortcuts.errors.path_taken"))
          false
        rescue ActiveRecord::RecordInvalid
          false
        end

        def validate(ctx, shortcut:, params:, **)
          input = params.to_h.symbolize_keys
          attrs = { path: input.key?(:path) ? input[:path] : shortcut.path }
          if input.key?(:target)
            match = Save::TARGET.match(input[:target].to_s)
            attrs.merge!(target_type: match && match[1], target_id: match && match[2].to_i)
          else
            attrs.merge!(target_type: shortcut.target_type, target_id: shortcut.target_id)
          end
          contract = ctx[:contract] = Contracts::Shortcut.new(shortcut)
          return true if contract.validate(attrs.stringify_keys)

          contract.errors.each { |error| shortcut.errors.add(error.attribute, error.message) }
          false
        end

        def persist(ctx, shortcut:, contract:, **)
          contract.sync
          shortcut.save!
          true
        end
      end

      def self.call(shortcut:, params:, customer_id:)
        signal, = Workflow.call([{ shortcut: shortcut, params: params, customer_id: customer_id }, {}])
        Result.new(success?: signal.to_h[:semantic] == :success, model: shortcut,
                   errors: shortcut.errors.messages.to_h)
      end
    end
  end
end
