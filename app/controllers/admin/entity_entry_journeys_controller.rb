# frozen_string_literal: true

module Admin
  # Starts a launched journey from one record (POST from the record's page,
  # Journeys::RecordStarts): the run begins holding the record, and the admin
  # lands on the journey's first page with it locked in, or editing it when
  # that step updates it. Authorization is the admin-or-owner path gate in
  # RouteAuthorization; the entity and entry are scoped to the URL customer.
  class EntityEntryJourneysController < ApplicationController
    include PageAudienceRouting

    before_action :find_entity
    before_action :find_entry

    def create
      start = Journeys::RecordStarts.new(entity: @entity, customer_id: current_customer.id, entry: @entry).find(params[:key])
      unless start
        return redirect_to(admin_entity_entry_path(current_customer.id, @entity, @entry), alert: t("journeys.runtime.unavailable"),
                                                                                           status: :see_other)
      end

      token = Journeys::RecordStarts.begin!(start: start, entry: @entry, viewer: current_user, session: session)
      step = start.journey.steps_definition.first_page_step
      path = run_step_surface_path(step, start.page, token, entry_id: @entry.id, audience: EntityAttributeAudience::ADMIN)
      redirect_to path || admin_entity_entry_path(current_customer.id, @entity, @entry), status: :see_other
    end

    private

    def find_entity
      @entity = Entity.where(customer_id: current_customer.id).or(Entity.shared).active.non_bridge.find(params[:entity_id])
    end

    def find_entry
      @entry = EntityEntry.where(customer_id: current_customer.id, entity_id: @entity.id).find(params[:entry_id])
    end
  end
end
