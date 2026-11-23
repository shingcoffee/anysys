# frozen_string_literal: true

module Admin
  module Maintenance
    # When the request is a Shared Resources URL, named helpers that would
    # generate tenant maintenance paths for Constants/Entities/Flowcharts/Pages
    # are rewritten to the matching `admin_maintenance_platform_*` helpers so
    # existing views and redirects keep working on the remounted controllers.
    module PlatformPathHelper
      PATH_PATTERN = %r{\A/81721200/admin/maintenance/platform/(constants|entities|flowcharts|pages)(?:[/.]|\z)}

      def shared_resources_mode?
        Current.shared_resources_mode == true
      end

      # Destroy (and other global CUD) of a shared row is allowed only on the
      # Shared Resources prefix. Customer-owned rows are always destroyable by
      # their tenant admin. The owner on a tenant URL is still a customer.
      def can_destroy_definition?(record)
        return false unless record
        return true if record.respond_to?(:customer_owned?) && record.customer_owned?

        record.respond_to?(:shared?) && record.shared? && shared_resources_mode?
      end

      # Duplicate a customer-owned row, or a shared row on the platform prefix
      # (another shared resource). Tenant-path copy of a shared row is gone —
      # per-customer overrides replace copy-to-customer.
      def can_copy_definition?(record)
        return false unless record
        return true if record.respond_to?(:customer_owned?) && record.customer_owned?

        record.respond_to?(:shared?) && record.shared? && shared_resources_mode?
      end

      # Halt a write that would mutate the global shared row off the platform
      # prefix. Returns true when the request was rejected (caller should stop).
      def reject_shared_global_mutation!(record, html_redirect:, json_error: "shared_resource_readonly")
        return false unless record.respond_to?(:shared?) && record.shared?
        return false if shared_resources_mode?

        respond_to do |format|
          format.html { redirect_to html_redirect, alert: I18n.t("maint_core.flash.shared_resources.platform_path_only") }
          format.json { render json: { error: json_error }, status: :forbidden }
          format.any  { head :forbidden }
        end
        true
      end

      def install_platform_path_overrides
        Admin::Maintenance::PlatformPathHelper.install_if_needed!
        Current.shared_resources_mode = request.path_info.match?(PATH_PATTERN)
      end

      # Prepended onto the route helpers module so these wrappers sit in front
      # of `admin_maintenance_*` path/url methods.
      module Overrides
      end

      def self.prepended(base)
        return unless base.respond_to?(:before_action)
        return if base.instance_variable_get(:@_platform_path_helper_installed)

        base.instance_variable_set(:@_platform_path_helper_installed, true)
        base.prepend_before_action :install_platform_path_overrides
      end

      def self.install_if_needed!
        return if Overrides.instance_methods.any?

        routes = Rails.application.routes
        routes.eager_load! if routes.respond_to?(:eager_load!)
        install!(routes)
      end

      def self.install!(routes)
        names = routes.named_routes.names.map(&:to_s)
        names.each do |name|
          next unless name.include?("admin_maintenance_")
          next if name.include?("admin_maintenance_platform_")

          platform_name = name.sub("admin_maintenance_", "admin_maintenance_platform_")
          next unless names.include?(platform_name)

          %w[path url].each do |suffix|
            tenant_helper = "#{name}_#{suffix}"
            platform_helper = "#{platform_name}_#{suffix}"
            next if Overrides.method_defined?(tenant_helper)

            Overrides.define_method(tenant_helper) do |*args, **kwargs, &block|
              if Current.shared_resources_mode
                public_send(platform_helper, *args, **kwargs, &block)
              else
                super(*args, **kwargs, &block)
              end
            end
          end
        end
      end
    end
  end
end
