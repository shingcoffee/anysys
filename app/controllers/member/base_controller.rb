# frozen_string_literal: true

module Member
  # Base controller for /:cid/member/* — the member-facing portal.
  #
  # Authorization is composed from three layers:
  #
  #   1. URL gate     — inherited from app/controllers/concerns/route_authorization.rb,
  #                     which gates /:cid/member/* on current_user.member?
  #                     and rejects with CanCan::AccessDenied otherwise.
  #   2. Tenant gate  — inherited from app/controllers/concerns/tenant_context.rb,
  #                     which redirects cross-tenant access to the user's own
  #                     /:cid/admin/dashboard.
  #   3. Record gate  — authorize_owned!(record), defined here. Controllers
  #                     call this before rendering or mutating a specific
  #                     record; mismatches raise ActiveRecord::RecordNotFound.
  #
  # See docs/superpowers/specs/2026-05-15-member-skeleton-design.md §7
  # for the full contract and the test cases that lock it in.
  class BaseController < ApplicationController
    layout "member"

    helper_method :current_member, :member_nav_items

    private

    def current_member
      current_user
    end

    def member_nav_items
      Member::Navigation.items_for(current_user)
    end

    # Record gate. Raises ActiveRecord::RecordNotFound (404) when:
    #   - the record is missing,
    #   - the record belongs to a different tenant, or
    #   - the record has a user_id and it doesn't match current_user.id.
    # Tenant mismatch should already have been caught by TenantContext, so the
    # tenant check here is a defense-in-depth assertion.
    def authorize_owned!(record)
      raise ActiveRecord::RecordNotFound unless record &&
        record.customer_id == current_user.customer_id &&
        (!record.respond_to?(:user_id) || record.user_id == current_user.id)
    end
  end
end
