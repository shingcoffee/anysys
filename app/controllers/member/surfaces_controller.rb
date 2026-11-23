# frozen_string_literal: true

module Member
  # Generic index/show controller for descriptor-driven member surfaces.
  # The descriptor is fetched by params[:key]; the scope, columns, and detail
  # layout come from the registered Member::Surface.
  class SurfacesController < BaseController
    # Same-tenant admins/owners may GET/HEAD a member surface (read-only
    # preview). Writes stay member-only; cross-tenant access stays blocked.
    # Index/show are the only actions. Scopes run with current_user, and show
    # re-checks the record through authorize_surface_record!.
    allow_admin_member_preview!

    before_action :load_surface

    def index
      scope = @surface.index.scope.call(current_user)
      @records, @page_meta = Member::PageFilters.paginate(
        scope, page: params[:page], per_page: @surface.index.per_page_or_default
      )
      prime_display!(@records)
      render "member/surfaces/index"
    end

    def show
      @record = @surface.index.scope.call(current_user).find_by(id: params[:id])
      authorize_surface_record!(@record)
      prime_display!([@record])
      @record_rows = Member::RecordRows.call(record: @record, viewer: current_user, customer: current_customer)
      @journey_starts = record_journey_starts(@record)
      render "member/surfaces/show"
    end

    private

    # The member journeys this record starts (Journeys::RecordStarts); none
    # in an admin's read-only preview, since starting one writes a run.
    def record_journey_starts(record)
      return [] unless record.is_a?(EntityEntry) && current_user.member?

      entity = Entity.where(customer_id: current_customer.id).or(Entity.shared).active.non_bridge.find_by(id: record.entity_id)
      return [] unless entity

      ::Journeys::RecordStarts.new(entity: entity, customer_id: current_customer.id, audience: EntityAttributeAudience::MEMBER,
                                   entry: record).all
    end

    def load_surface
      @surface = Member::Surfaces.fetch(params[:key], customer: current_customer)
      raise ActiveRecord::RecordNotFound unless @surface.enabled_for?(current_user)
      raise ActiveRecord::RecordNotFound if @surface.descriptor.is_a?(Member::Sources::BuiltinSurface)
    end

    # Entity rows come from People::Ownership.scope, which already limits them
    # to the member; owned rows (e.g. enrollments) carry no user_id of their own.
    def authorize_surface_record!(record)
      return authorize_owned!(record) unless record.is_a?(EntityEntry)

      raise ActiveRecord::RecordNotFound unless record.customer_id == current_user.customer_id
    end

    # Entity-backed rows read display text for the member's audience; other
    # records pass through untouched.
    def prime_display!(records)
      ::Entities::EntryDisplay.prime!(records, customer_id: current_customer.id, viewer: current_user,
                                               audience: EntityAttributeAudience.for_user(current_user, customer_id: current_customer.id))
    end
  end
end
