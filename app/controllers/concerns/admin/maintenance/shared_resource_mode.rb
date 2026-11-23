# frozen_string_literal: true

module Admin
  module Maintenance
    # Switches the remounted Constants/Entities/Flowcharts/Pages controllers
    # between tenant maintenance and platform Shared Resources.
    module SharedResourceMode
      extend ActiveSupport::Concern

      included do
        helper_method :publishing_editable?, :tenant_override? if respond_to?(:helper_method)
      end

      class_methods do
        # Reject tenant-path writes that would mutate a shared parent row.
        # `record` is the instance-variable name. Call after the finder
        # before_action so the record is loaded.
        def guard_shared_global_writes(record, only: nil, json_error:, &redirect)
          filter = lambda {
            rec = instance_variable_get(record)
            error = json_error.respond_to?(:call) ? instance_exec(&json_error) : json_error
            reject_shared_global_mutation!(
              rec,
              html_redirect: instance_exec(&redirect),
              json_error: error
            )
          }
          only.nil? ? before_action(filter) : before_action(filter, only: Array(only))
        end
      end

      def definition_scope(klass)
        scope = shared_resources_mode? ? klass.shared : klass.accessible
        return scope if shared_resources_mode?

        preload_override_association(scope, klass)
      end

      def deleted_definition_scope(klass)
        if shared_resources_mode?
          klass.only_deleted.shared
        else
          klass.only_deleted.where(customer_id: current_customer_id)
        end
      end

      def apply_create_identity!(record)
        if shared_resources_mode?
          record.skip_tenant_customer_assignment! if record.respond_to?(:skip_tenant_customer_assignment!)
          record.customer_id = nil
        else
          record.customer = current_customer if record.respond_to?(:customer=)
        end
      end

      def require_copyable_source!(record)
        raise ActiveRecord::RecordNotFound unless can_copy_definition?(record)
      end

      def skip_quota_for_shared_create?(record)
        shared_record?(record)
      end

      def publishing_editable?(record)
        !shared_record?(record) || shared_resources_mode?
      end

      # Tenant-path Save of a shared row writes that customer's override, not
      # the global default (including when the URL customer is 81721200).
      def tenant_override?(record)
        shared_record?(record) && !shared_resources_mode?
      end

      private

      def preload_override_association(scope, klass)
        reflection = klass.try(:versionable_options)&.dig(:customer_head_reflection)
        return scope.includes(reflection) if reflection
        return scope.includes(:constant_customer_overrides) if klass.reflect_on_association(:constant_customer_overrides)

        scope
      end

      def scoped_deleted_resources
        return super unless shared_resources_mode? &&
                            self.class.respond_to?(:soft_deletable_resource_class) &&
                            soft_deletable_resource_class.respond_to?(:shared)

        soft_deletable_resource_class.only_deleted.shared
      end

      def shared_record?(record)
        record.respond_to?(:shared?) && record.shared?
      end
    end
  end
end
