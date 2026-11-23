# frozen_string_literal: true

# Public page surface for /:customer_id/page/:uuid
#
# `uuid` is always Page#public_uuid.
# GET  show   — render a launched page that includes the public audience.
# POST submit — run the page's flowchart (Pages::Submit), then
#               redirect (PageSubmissionNavigation).
#
# Access policy: GET renders when public is in the set, unless the viewer's
# audience has a counterpart in the same action (303). POST requires the
# viewer's audience; otherwise the submission is refused and nothing is
# written. After a successful submit, each audience returns to its surface.
class PublicPagesController < ApplicationController
  include CaptchaProtectable
  include PageRendering
  include PageAudienceRouting
  include PageEntityEntryReturn
  include PageSubmissionNavigation
  include PageShortcuts::RouteContext
  include PageShortcuts::PublicPathContext

  layout "public_page"

  rescue_from ActiveRecord::RecordNotFound, with: :render_page_not_found

  before_action :find_launched_page
  before_action :authorize_public_view!, only: :show
  before_action :redirect_to_audience_counterpart!, only: :show
  before_action :authorize_submission!,  only: :submit

  def show
    assign_page_continuation
    prepare_page_render(@page, prefill: page_prefill_values)
  end

  def submit
    return redirect_after_journey_skip if params[:_intent].to_s == Journeys::Advance::SKIP

    result = Pages::Submit.call(
      page: @page, params: params, customer: current_customer, viewer: page_runtime_user,
      bindings: page_bindings_for(@page), journey: submission_journey, account: journey_account,
      journey_record_id: journey_record_id(submit_journey_position),
      authentication: FlowchartRuntime::Authentication.from_request(request),
      user_agent: request.user_agent, session: session
    )
    redirect_after_submission(result)
  end

  private

  def find_launched_page
    @page = Page.accessible.launched.find_by!(public_uuid: params[:uuid])
  end

  # Reads require public in the set. A narrower page 404s for everyone.
  def authorize_public_view!
    raise ActiveRecord::RecordNotFound unless @page.visible_to?(:public)
  end

  # A viewer whose audience has another live page in this action is
  # sent there (303), keeping sanitized prefill.
  def redirect_to_audience_counterpart!
    counterpart = Pages::ActionResolver.counterpart(page: @page, audience: page_runtime_audience, customer_id: current_customer_id)
    return unless counterpart

    redirect_to audience_surface_path(counterpart, prefill: sanitized_action_prefill),
                status: :see_other
  end

  # Writes require the viewer's audience. Refusal order:
  # counterpart → anonymous sign-in store → public not_for_your_account → 404.
  # Nothing is written on any refusal.
  def authorize_submission!
    authorize_public_view! if page_shortcut_request?
    return if page_visible_to_current_viewer?

    counterpart = Pages::ActionResolver.counterpart(page: @page, audience: page_runtime_audience, customer_id: current_customer_id)
    if counterpart
      redirect_to audience_surface_path(counterpart), notice: t("public_views.actions.continue_here")
      return
    end

    if !user_signed_in? && (@page.visible_to?(:member) || @page.visible_to?(:admin))
      store_location_for(:user, stored_submission_return_path)
      redirect_to new_user_session_path
      return
    end

    if @page.visible_to?(:public)
      redirect_to public_page_location(@page), alert: t("public_views.actions.not_for_your_account")
      return
    end

    raise ActiveRecord::RecordNotFound
  end

  def page_visible_to_current_viewer?(page = @page)
    page.visible_to?(page_runtime_audience)
  end

  # After sign-in, Devise GETs this path. Member surface if the page includes
  # member; otherwise the admin render (an expired admin session lands back).
  def stored_submission_return_path
    if @page.visible_to?(:member)
      member_page_path(customer_id: params[:customer_id], id: @page.id)
    else
      admin_maintenance_page_render_path(params[:customer_id], @page)
    end
  end

  def public_page_location(page)
    path = PageShortcuts::PublicPath.public_page(
      page: page, customer_id: current_customer_id, host: request.host
    )
    uri = Addressable::URI.parse("#{request.script_name}#{path}")
    values = uri.query_values || {}
    values = values.merge("locale" => current_locale.to_s) if params[:locale].present?
    uri.query_values = values if values.present?
    uri.to_s
  end

  def render_page_not_found
    render plain: t("public_views.public_pages.not_found"), status: :not_found
  end

  def render_error(message, status:)
    respond_to do |format|
      format.html { render plain: message, status: status }
      format.any  { head status }
    end
  end

  def handle_captcha_rejection(_outcome)
    assign_page_continuation
    prepare_page_render(@page, prefill: page_prefill_values)
    render :show, status: :unprocessable_entity
  end

  # Query `continuation` on GET; posted `_continuation` on captcha re-render.
  # Only a verified token is kept so the hidden field is never forged HTML.
  def assign_page_continuation
    token = params[:continuation].presence || params[:_continuation]
    return unless token.is_a?(String)

    @page_continuation = token if Pages::Continuation.verify(token)
  end

  def page_prefill_values
    ::Pages::Prefill.values(
      page: @page, params: params, audience: page_runtime_audience, viewer: page_runtime_user
    )
  end
end
