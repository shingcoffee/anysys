# frozen_string_literal: true

# Prepares @form_action and @content for rendering a built page's generated
# ERB under an audience-specific layout. All audience surfaces submit to the
# public page UUID endpoint (PublicPagesController#submit).
module PageRendering
  extend ActiveSupport::Concern
  include JourneyNavigation

  # Submission `return_to` token: send an admin back to the page entity's
  # entries area (see PageEntityEntryReturn).
  ENTITY_ENTRY_RETURN = "entity_entry"

  included do
    helper_method :page_quick_add_depth, :page_form_options
  end

  private

  # +submit_params+ ride on the submit URL (e.g. the +return_to+ token).
  # +quick_add_depth+ is the Admin::Entities::QuickAddDialogComponent level
  # entity-backed dropdowns open with "+ Add New" (PageEntityQuickAddHelper);
  # nil offers none, and only admin surfaces set it.
  # +prefill+ is the display-only hash from Pages::Prefill.values.
  # +presentation+ goes to PageContentGenerator; +form+ (cancel_path:,
  # frame:) to the Admin::Pages::FormComponent the :entry presentation renders.
  def prepare_page_render(page, submit_params: {}, quick_add_depth: nil, prefill: {}, presentation: :themed, form: {})
    @form_action = public_page_submit_path(customer_id: current_customer_id, uuid: page.public_uuid, **submit_params)
    @page_quick_add_depth = quick_add_depth
    @page_prefill = prefill
    restore_refused_submission(page)
    @page_form_options = form.merge(action: @form_action)
    @page_bindings = page_bindings_for(page)
    assign_journey_context(page, starting: submit_params[:entry_id].blank?)
    @content = page.generate_content(presentation: presentation)
  end

  # The journey step this page renders as (progress, "Save and add another");
  # a previewed draft not yet running carries its key into the submit.
  def assign_journey_context(page, starting:)
    position = journey_position(page, starting: starting)
    return unless position

    @journey, @journey_step = position.journey, position.step
    @journey_start_key = position.journey.key if position.run.nil? && position.journey.draft?
  end

  # The visitor's run from the query (`run`) or the posted hidden field
  # (`_run`); only a run usable by this viewer is kept, and only then is its
  # token echoed back into the form.
  def page_run
    return @page_run if defined?(@page_run)

    token = params[:run].presence || params[:_run]
    @page_run = JourneyRun.find_usable(token: token, customer_id: current_customer_id, user: current_user, session: session)
    @page_run_token = token if @page_run
    @page_run
  end

  # A refused submit of this page comes back once with what was typed (still
  # under the prefill rules) and each field's errors (PageFieldErrorsHelper).
  def restore_refused_submission(page)
    kept = page_run && Pages::SubmissionRetry.take(page_run, page)
    return unless kept

    typed = Pages::Prefill.values(page: page, params: { "prefill" => kept["values"] },
                                  audience: page_runtime_audience, viewer: page_runtime_user)
    @page_prefill = @page_prefill.to_h.merge(typed)
    @page_field_errors = kept["field_errors"]
  end

  def page_bindings_for(page)
    Pages::InputBindings.resolve(page: page, run: page_run, viewer: page_runtime_user,
                                 audience: page_runtime_audience, customer_id: current_customer_id)
  end

  def page_quick_add_depth
    @page_quick_add_depth
  end

  # The "+ Add New" dialog keeps its submit in the frame, so neither a journey
  # nor "go to page" may move it.
  def quick_add_frame_request?
    turbo_frame_request? && Admin::Entities::QuickAddDialogComponent.depth_of(request.headers["Turbo-Frame"]).present?
  end

  def page_form_options
    @page_form_options || { action: @form_action }
  end

  def page_runtime_user
    user = current_user
    user if EntityAttributeAudience.tenant_viewer?(user, customer_id: current_customer_id)
  end

  def page_runtime_audience
    EntityAttributeAudience.for_user(current_user, customer_id: current_customer_id)
  end
end
