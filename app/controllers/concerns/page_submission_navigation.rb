# frozen_string_literal: true

# Where a page submission sends the visitor, decided in one place from the
# Pages::Submit result:
#
#   refused/rejected/offline/failed → back to the page (typed values and field
#                                     errors kept on the visitor's run)
#   success → a module handoff, else the journey's next step, else the admin
#             entry return, else the page's own landing
#
# The flash names the most specific message: the flowchart's outcome, then
# the journey's notice, the page's success message, the entry return's.
module PageSubmissionNavigation
  extend ActiveSupport::Concern

  private

  def redirect_after_journey_skip
    move = journey_skip
    return redirect_to(retry_path, alert: t("journeys.runtime.skip_unavailable")) unless move

    redirect_to move.path, notice: move.notice
  end

  def redirect_after_submission(result)
    case result.status
    when :success then complete_submission(result)
    when :failed then redirect_with_refusal(result)
    when :rejected, :offline then redirect_to(retry_path, alert: result.message)
    when :refused
      return render_error(result.message, status: :method_not_allowed) if result.http_status == :method_not_allowed

      redirect_with_submission_error
    end
  end

  # A handoff always goes through the framework hop, which leaves Turbo Drive
  # and enters the module with a top-level navigation. The journey still
  # records the step, so a checkout that ends it leaves the run completed.
  def complete_submission(result)
    if result.handed_off
      journey_move(result) if result.entry
      return redirect_to(feature_module_handoff_path(current_customer_id))
    end

    move = result.entry && journey_move(result)
    landing = result.entry && !move && (entity_entry_landing(result.entry) || member_row_landing(result.entry))
    outcome = result.outcome.to_h
    text = outcome_message(outcome) || move&.notice || @page.success_message || (landing && landing[:notice]) ||
           t("public_views.flash.response_submitted")
    path = move&.path || (landing && landing[:path]) || post_submit_path
    redirect_to path, outcome_flash_type(outcome) => text, flash: (landing && landing[:flash]).presence
  end

  # A member who added or changed a row of their own record (Pages::MemberRows)
  # goes back to that record.
  def member_row_landing(entry)
    return unless page_runtime_audience == EntityAttributeAudience::MEMBER && Pages::MemberRows.managing?(@page)

    record = Pages::MemberRows.record_of(page: @page, row: entry, viewer: page_runtime_user, customer_id: current_customer_id)
    { path: member_surface_path(current_customer_id, "entity_#{record.entity_id}", record.id), notice: nil, flash: {} } if record
  end

  def outcome_message(outcome)
    return if outcome["preset"].blank?

    text = FlowchartRuntime::LocalizedText.resolve(outcome["message"], locale: I18n.locale)
    return text if text.present?

    key = "public_views.flash.outcomes.#{outcome['preset']}"
    I18n.exists?(key) ? t(key) : t("public_views.flash.response_submitted")
  end

  def outcome_flash_type(outcome)
    outcome["preset"].present? && outcome["flash"].to_s == "alert" ? :alert : :notice
  end

  def redirect_with_submission_error(collected_errors = nil)
    redirect_to retry_path,
                alert: t("public_views.flash.response_save_error",
                         errors: collected_errors.presence || t("common.errors.dynamic.activity_execution_failed"))
  end

  # The form comes back with what was typed and each field's errors beside
  # it, kept on the visitor's run; the alert carries only the rest.
  def redirect_with_refusal(result)
    issued = Pages::SubmissionRetry.store(
      run: page_run, page: @page, values: result.values, field_errors: result.field_errors,
      customer_id: current_customer_id, user: page_runtime_user, session: session
    )
    @page_run_token = issued if issued
    return redirect_with_submission_error(result.message) if result.message.present? || result.field_errors.blank?

    redirect_to retry_path, alert: t("public_views.flash.response_field_errors")
  end

  # Sends the viewer back to the surface of their audience; an admin who
  # submitted from the entity's entries area, back to its entry form, otherwise
  # to the form's catalog tab.
  def post_submit_path(page = @page)
    case page_runtime_audience
    when EntityAttributeAudience::MEMBER
      member_page_path(customer_id: params[:customer_id], id: page.id)
    when EntityAttributeAudience::ADMIN
      entity_entry_return?(page) ? entity_entry_form_path : Admin::Pages::BrowsePath.for(page, customer_id: current_customer_id)
    else
      public_page_location(page)
    end
  end

  # A refused submission goes back to the same page, keeping its run so the
  # locked inputs survive the retry; an admin who opened a specific page from
  # the entries area (`page` on the submit URL) gets that page again, and a
  # member who was changing a record gets that record again.
  def retry_path
    page = @page if entity_entry_return? && params[:page].to_s == @page.id.to_s
    page_run
    Pages::RunLink.append(member_retry_path || post_submit_path, @page_run_token, page: page)
  end

  def member_retry_path
    return unless page_runtime_audience == EntityAttributeAudience::MEMBER && edited_entity_entry_id

    member_page_path(customer_id: params[:customer_id], id: @page.id, entry: edited_entity_entry_id)
  end
end
