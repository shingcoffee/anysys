# frozen_string_literal: true

module Admin
  # Link a person-entity entry to a same-tenant user account.
  # Authorization is the admin-or-owner path gate in RouteAuthorization
  # (enforce_route_role! → current_user.admin_or_owner?). Tenant isolation
  # is the URL customer: entries and candidate users are scoped through
  # current_customer, so an owner on another tenant's URL still only sees
  # that tenant's users.
  class EntityEntryPersonLinksController < ApplicationController
    before_action :find_entity
    before_action :find_entry

    def create
      raise ActionController::BadRequest if params[:user_id].blank?

      result = People::Link.link!(entry: @entry, user_id: params[:user_id], actor: current_user)
      redirect_after_link(result, notice: t("admin_misc.person_link.flash.linked"))
    end

    def candidates
      return head :not_acceptable unless request.format.json?

      users = People::Link.candidates(
        entry: @entry,
        query: params[:q].to_s.strip.first(100)
      )
      render json: {
        users: users.map { |user| { id: user.id, name: user.display_name, email: user.email } }
      }
    end

    private

    def redirect_after_link(result, notice:)
      path = admin_entity_entry_path(current_customer.id, @entity, @entry)
      if result.success?
        redirect_to path, notice: notice, status: :see_other
      else
        redirect_to path, alert: result.errors.to_sentence, status: :see_other
      end
    end

    def find_entity
      scope = Entity.where(customer_id: current_customer.id).or(Entity.shared)
      scope = scope.active if action_name == "create"
      @entity = scope.find(params[:entity_id])
      raise ActiveRecord::RecordNotFound unless @entity.person?
    end

    def find_entry
      @entry = EntityEntry.where(customer_id: current_customer.id, entity_id: @entity.id)
                          .find(params[:entry_id])
    end
  end
end
