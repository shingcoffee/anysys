# frozen_string_literal: true

module Admin
  module Modules
    module Authentication
      # Creates a person-entity entry from the user detail page and links it to
      # that user. Admin/owner-only via RouteAuthorization (admin path); the
      # user and entity are resolved through the URL customer, so another
      # tenant's ids 404.
      class UserProfilesController < ApplicationController
        dashboard_menu_item :modules

        before_action :find_user
        before_action :find_entity

        def create
          signal, ctx = ::People::Activities::CreateLinkedEntry.call(
            customer: current_customer, actor: current_user, user: @user, entity: @entity, params: entry_data_params
          )

          case signal.to_h[:semantic]
          when :success
            redirect_to admin_modules_authentication_user_path(current_customer_id, @user),
                        notice: t("admin_modules.flash.users.profile_created", entity: @entity.display_label),
                        status: :see_other
          when :already_linked
            redirect_to admin_modules_authentication_user_path(current_customer_id, @user),
                        alert: t("people.errors.user_already_linked"), status: :see_other
          when :forbidden
            raise CanCan::AccessDenied, t("common.flash.access_denied")
          else
            @trusted_devices = @user.trusted_devices.active.order(last_used_at: :desc)
            @profile_sections = ::Authentication::UserDomainProfiles.call(
              user: @user, customer: current_customer, viewer: current_user, forms: { @entity.id => ctx[:form] }
            )
            render "admin/modules/authentication/users/show", status: :unprocessable_entity
          end
        end

        private

        def find_user
          @user = ::Authentication::User.where(customer_id: current_customer_id).find(params[:user_id])
        end

        def find_entity
          @entity = EntityDomains::Catalog.entities(current_customer.id).active.non_bridge.find(params[:entity_id])
          raise ActiveRecord::RecordNotFound unless @entity.person?
        end

        def entry_data_params
          entry = params[:entry]
          data = entry[:data] if entry.is_a?(ActionController::Parameters)
          raise ActionController::BadRequest unless data.is_a?(ActionController::Parameters)

          data
        end
      end
    end
  end
end
