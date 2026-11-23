# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Authentication
        class RoleGrantsController < ApplicationController
          dashboard_menu_item :settings
          before_action :set_role

          def show
            @catalog = AccessPoints::Catalog.for(customer_id: current_customer.id)
            @granted_keys = grant_lookup_set(@role)
          end

          def update
            result = RoleGrants::Operation::Update.call(
              role:    @role,
              added:   permitted_params[:added]   || [],
              removed: permitted_params[:removed] || [],
              actor:   current_user
            )

            respond_to do |format|
              if result.success?
                format.json { render json: { ok: true } }
                format.html { redirect_to admin_settings_modules_authentication_role_grants_path(current_customer.id, @role),
                                          notice: t("admin_settings.flash.role_grants.updated") }
              else
                format.json { render json: { ok: false, errors: result.errors }, status: :unprocessable_entity }
                format.html { redirect_back fallback_location: admin_settings_modules_authentication_roles_path(current_customer.id),
                                            alert: t("admin_settings.flash.role_grants.update_failed") }
              end
            end
          end

          private

          def set_role
            @role = current_customer.roles.find(params[:role_id])
          end

          def permitted_params
            params.require(:role_grants).permit(
              added:   [:subject_type, :subject_key, :subject_id, :action],
              removed: [:subject_type, :subject_key, :subject_id, :action]
            )
          end

          def grant_lookup_set(role)
            role.role_permissions.pluck(:subject_type, :subject_key, :subject_id, :action)
                .map { |st, sk, sid, a| "#{st}:#{sk}:#{sid}:#{a}" }
                .to_set
          end
        end
      end
    end
  end
end
