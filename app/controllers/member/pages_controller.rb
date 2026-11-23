# frozen_string_literal: true

module Member
  # Renders a built page exactly as the member audience sees it
  # (member layout). Pages are tenant records, not member-owned, so the
  # gate is tenant scope + launched + member in the audience set (no user_id check).
  # `entry` names a row the member manages from their own record
  # (Pages::MemberRows), or the record their journey run's current update
  # step edits, which the page then changes instead of adding one — the same
  # rule its submit applies (Pages::Submission::Target).
  #
  # Same-tenant admins/owners may also GET this render directly — the
  # "Open" link on the admin page detail — via the RouteAuthorization
  # opt-in below. The audience gate still applies: member must be in the set.
  class PagesController < BaseController
    include PageRendering

    allow_admin_member_preview!

    def show
      @page = Page.accessible.launched.find(params[:id])
      raise ActiveRecord::RecordNotFound unless @page.visible_to?(:member)

      entry = edited_entry
      prepare_page_render(@page, submit_params: { entry_id: entry&.id }.compact, prefill: page_prefill(entry))
    end

    private

    def edited_entry
      return if params[:entry].blank?
      raise ActiveRecord::RecordNotFound unless @page.entity

      target = ::Pages::Submission::Target.resolve(
        page: @page, entity: @page.entity, entry_id: params[:entry].to_s, audience: EntityAttributeAudience::MEMBER,
        viewer: page_runtime_user, customer_id: current_customer.id,
        journey_record_id: journey_record_id(journey_position(@page, starting: false))
      )
      raise ActiveRecord::RecordNotFound unless target.is_a?(::Pages::Submission::Target)

      target.record
    end

    def page_prefill(entry)
      if entry
        ::Pages::EntryPrefill.values(page: @page, entry: entry, audience: page_runtime_audience)
      else
        ::Pages::Prefill.values(page: @page, params: params, audience: page_runtime_audience, viewer: page_runtime_user)
      end
    end
  end
end
