# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Authentication
        class UserRoleAssignmentsController < ApplicationController
          dashboard_menu_item :settings

          def index
            @users = ::Authentication::User.where(customer_id: current_customer.id)
                                           .includes(:roles)
                                           .order(:last_name, :first_name)
            @roles = current_customer.roles.order(:system, :name)
          end

          def create
            user = ::Authentication::User.where(customer_id: current_customer.id).find(params[:user_id])
            result = UserRoles::Operation::Assign.call(
              user: user, role_ids: params[:role_ids], actor: current_user, request: request
            )
            respond_to do |format|
              if result.success?
                format.json { render json: { ok: true } }
                format.html { redirect_to admin_settings_modules_authentication_user_role_assignments_path(current_customer.id),
                                          notice: t("admin_settings.flash.user_role_assignments.assigned") }
              else
                format.json { render json: { ok: false, errors: result.errors }, status: :unprocessable_entity }
                format.html { redirect_back fallback_location: admin_settings_modules_authentication_user_role_assignments_path(current_customer.id),
                                            alert: t("admin_settings.flash.user_role_assignments.assign_failed") }
              end
            end
          end

          def destroy
            ur = UsersRole.joins(:user).where(users: { customer_id: current_customer.id }).find(params[:id])

            # Preserve the non-owner response; the model policy also makes the
            # owner assignment immutable for the owner themselves.
            if ur.user.owner? && !current_user&.owner?
              ur.errors.add(:base, t("auth.errors.owner_role_protected"))
              return render_assignment_removal_failure(ur)
            end

            return render_assignment_removal_failure(ur) unless UserRoles::AssignmentPolicy.removable?(ur)

            ur.user.with_lock(requires_new: true) do
              before_role_ids = ur.user.users_roles.pluck(:role_id)
              ur.destroy!
              ::Authentication::MutationAudit.roles(user: ur.user, before_role_ids: before_role_ids,
                                                     request: request, actor: current_user)
            end
            redirect_to admin_settings_modules_authentication_user_role_assignments_path(current_customer.id),
                        notice: t("admin_settings.flash.user_role_assignments.removed")
          rescue ActiveRecord::RecordNotDestroyed => error
            # The model rechecks under the account lock, including when a role
            # changes after the controller's initial policy check.
            render_assignment_removal_failure(error.record)
          end

          private

          def render_assignment_removal_failure(record)
            messages = record.errors.full_messages.presence || [t("auth.errors.role_removal_failed")]
            respond_to do |format|
              format.json { render json: { ok: false, errors: { base: messages } }, status: :unprocessable_entity }
              format.html do
                redirect_to admin_settings_modules_authentication_user_role_assignments_path(current_customer.id),
                            alert: messages.to_sentence
              end
            end
          end
        end
      end
    end
  end
end
