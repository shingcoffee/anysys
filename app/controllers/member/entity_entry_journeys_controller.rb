# frozen_string_literal: true

module Member
  # Starts a launched member journey from one of the member's own records
  # (POST from the record's member page, Journeys::RecordStarts): the run
  # begins holding the record, and the member lands on the journey's first
  # page with it locked in, or changing it when that step updates it.
  # Member-only through RouteAuthorization (no admin preview: this writes a
  # run); the entity is scoped to the URL customer and the record must be one
  # the member reaches (People::Ownership), re-checked here.
  class EntityEntryJourneysController < BaseController
    include PageAudienceRouting

    MEMBER = EntityAttributeAudience::MEMBER

    before_action :find_entity
    before_action :find_entry

    def create
      start = Journeys::RecordStarts.new(entity: @entity, customer_id: current_customer.id, audience: MEMBER, entry: @entry)
                                    .find(params[:key])
      return redirect_to(record_path, alert: t("journeys.runtime.unavailable"), status: :see_other) unless start

      token = Journeys::RecordStarts.begin!(start: start, entry: @entry, viewer: current_user, session: session)
      step = start.journey.steps_definition.first_page_step
      redirect_to run_step_surface_path(step, start.page, token, entry_id: @entry.id, audience: MEMBER) || record_path,
                  status: :see_other
    end

    private

    def find_entity
      @entity = Entity.where(customer_id: current_customer.id).or(Entity.shared).active.non_bridge.find(params[:entity_id])
    end

    def find_entry
      reachable = People::Ownership.reachable_ids(@entity, [params[:entry_id].to_s], viewer: current_user, audience: MEMBER,
                                                                                      customer_id: current_customer.id)
      raise ActiveRecord::RecordNotFound if reachable.empty?

      @entry = EntityEntry.where(customer_id: current_customer.id, entity_id: @entity.id).find(reachable.first)
    end

    def record_path = member_surface_path(current_customer.id, "entity_#{@entity.id}", @entry.id)
  end
end
