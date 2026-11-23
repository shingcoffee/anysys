# frozen_string_literal: true

module Admin
  module Modules
    module Sms
      class EntitySyncsController < BaseController
        def new
          raw = action_attributes(:entity_id)
          @form_values = ::Sms::FormValues.entity_sync.merge(raw)
          if raw.key?(:entity_id)
            @form_values[:entity_id] = ::Sms::RequestAttributes.integer(raw[:entity_id], field: :entity_id, optional: true, minimum: 1)
          end
          prepare_sources
          render_sync
        end

        def preview
          synchronize(preview: true)
        end

        def create
          synchronize(preview: false)
        end

        private

        def synchronize(preview:)
          attributes = form_attributes(:entity_sync)
          @form_values = ::Sms::FormValues.entity_sync.merge(@form_values)
          prepare_sources
          result = ::Sms::Contacts::SyncEntity.call(customer: current_customer, actor: current_user, attributes: attributes, preview: preview)
          if result.success?
            @sync_result = result.value
            # Retain the exact high-water bound for the explicit next request.
            @form_values[:through_entry_id] = @sync_result[:through_entry_id]
            render_sync
          else
            render_failure(result, template: :new)
          end
        end

        def prepare_sources
          catalog = ::Sms::EntitySources.new(customer: current_customer)
          @entities = catalog.entities
          selected = ::Sms::RequestAttributes.integer(@form_values[:entity_id], field: :entity_id, optional: true, minimum: 1)
          @source_fields = catalog.fields(selected)
          @errors ||= {}
          @sync_result ||= nil
        end

        def render_sync
          render_surface(:new, data: { form_values: @form_values, entities: @entities, source_fields: @source_fields, sync_result: @sync_result, errors: @errors })
        end

        def input_error(error)
          @errors = error.errors
          @form_values = ::Sms::FormValues.entity_sync.merge(@form_values || {}).merge(error.form_values)
          @entities = ::Sms::EntitySources.new(customer: current_customer).entities
          @source_fields = { phone: [], scalar: [] }
          begin
            prepare_sources
          rescue ::Sms::RequestAttributes::Invalid, ActiveRecord::RecordNotFound
            # Invalid selection remains in the form; it never selects a substitute.
          end
          render_failure(error, template: :new)
        end
      end
    end
  end
end
