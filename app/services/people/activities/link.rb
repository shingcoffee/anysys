# frozen_string_literal: true

module People
  module Activities
    class Link < Trailblazer::Activity::Railway
      step :validate
      step :persist
      fail :collect_errors

      def self.call(entry:, user_id:, actor:, event: "person.linked")
        Customer.find(entry.customer_id).with_lock(requires_new: true) do
          entry.reload
          signal, (ctx, _) = super([{ entry: entry, user_id: user_id, actor: actor, event: event, errors: [] }, {}])
          People::Link::Result.new(
            success?: signal.to_h[:semantic] == :success,
            entry: ctx[:entry] || entry,
            errors: Array(ctx[:errors])
          )
        end
      rescue ActiveRecord::RecordNotUnique
        People::Link::Result.new(
          success?: false,
          entry: entry,
          errors: [I18n.t("people.errors.user_already_linked")]
        )
      end

      def validate(ctx, entry:, user_id:, **)
        contract = ctx[:contract] = People::Contracts::Link.new(entry)
        contract.validate("user_id" => user_id)
      end

      def persist(ctx, entry:, user_id:, actor:, event:, **)
        data = entry.data_json
        data = data.is_a?(Hash) ? data.stringify_keys.except(*People::IDENTITY_KEYS) : {}
        entry.user_id = user_id
        entry.data_json = data
        entry.save!(validate: false)

        Authentication::AuditLog.record(
          event: event,
          user: actor,
          customer_id: entry.customer_id,
          entry_id: entry.id,
          entity_id: entry.entity_id,
          linked_user_id: entry.user_id
        )
        ctx[:entry] = entry
        true
      end

      def collect_errors(ctx, contract: nil, **)
        ctx[:errors] = contract ? contract.errors.full_messages : Array(ctx[:errors])
        true
      end
    end
  end
end
