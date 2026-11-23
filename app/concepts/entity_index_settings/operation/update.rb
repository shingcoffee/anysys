# frozen_string_literal: true

module EntityIndexSettings
  module Operation
    class Update
      Result = Struct.new(:success?, :errors, keyword_init: true) do
        def [](k) = send(k)
      end

      # @param customer [Customer]
      # @param entity [Entity]
      # @param params [ActionController::Parameters | Hash] expects { visible_column_keys: [...] }
      def self.call(customer:, entity:, params:)
        payload = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
        keys = Array(payload[:visible_column_keys] || payload["visible_column_keys"])
                 .map(&:to_s)
                 .reject(&:blank?)

        system = Admin::Entities::ColumnsBuilder::SYSTEM_KEYS.map(&:to_s)
        # Derived slugs (computed and calculated) are offered by the column picker even though nothing is stored for them, so they must be selectable here.
        selectable = entity.input_fields + entity.computed_fields + entity.calculated_fields
        allowed = selectable.filter_map { |f| f["name_slug"].presence } - system

        form = Contract::Update.new(OpenStruct.new(visible_column_keys: keys))
        form.allowed_slugs = allowed
        unless form.validate(visible_column_keys: keys)
          return Result.new(success?: false, errors: form.errors)
        end

        persist!(customer_id: customer.id, entity_id: entity.id, keys: keys)
        Result.new(success?: true, errors: nil)
      end

      def self.persist!(customer_id:, entity_id:, keys:)
        setting = EntityIndexSetting.for(customer_id: customer_id, entity_id: entity_id)
        setting.write_overlay(visible_column_keys: keys)
        setting.save!
      rescue ActiveRecord::RecordNotUnique
        setting = EntityIndexSetting.for(customer_id: customer_id, entity_id: entity_id)
        setting.write_overlay(visible_column_keys: keys)
        setting.save!
      end
      private_class_method :persist!
    end
  end
end
