# frozen_string_literal: true

# Where the viewer is in a journey, on render and on submit alike: the run's
# current step when that step is this page, else the first step of the journey
# a new record here would start. A dialog frame is never part of a journey.
# After a successful submit, `journey_move` advances the run (issuing it on
# the first step) and names the next destination.
module JourneyNavigation
  extend ActiveSupport::Concern

  Position = Data.define(:journey, :step, :run)
  Move = Data.define(:path, :notice)

  private

  def journey_position(page, starting:)
    return @journey_position if defined?(@journey_position)

    @journey_position =
      if quick_add_frame_request?
        nil
      elsif (run = page_run)&.journey
        step = run.journey.steps_definition.step(run.current_step)
        Position.new(journey: run.journey, step: step, run: run) if step && step.action_key == page.action_key
      elsif starting && (journey = starting_journey(page))
        Position.new(journey: journey, step: journey.steps_definition.first_step, run: nil)
      end
  end

  # The launched journey this page starts for the viewer, or the draft the
  # platform owner previews (`journey` on the URL, `_journey` once posted).
  def starting_journey(page)
    Journeys::Starter.for_page(page: page, audience: page_runtime_audience, customer_id: current_customer_id) ||
      Journeys::Starter.preview(key: params[:journey].presence || params[:_journey], page: page,
                                customer_id: current_customer_id, viewer: current_user)
  end

  def submit_journey_position = journey_position(@page, starting: params[:entry_id].blank?)

  # The journey and step a submit belongs to, as the page's flowchart sees them.
  def submission_journey
    position = submit_journey_position
    return unless position

    finishing = Journeys::Advance.finishing?(journey: position.journey, step: position.step, run: position.run, intent: params[:_intent])
    { "key" => position.journey.key, "step" => position.step.key, "finishing" => finishing }
  end

  # The record +position+'s run step edits when it is an update step: a member
  # may change it while their run is there (Pages::Submission::Target).
  def journey_record_id(position)
    step = position&.run && position.step
    Array(position.run.records[step.record]).last&.to_s if step&.update?
  end

  # The account a journey's user step created, while an admin's run is on the
  # step whose new record is linked to it.
  def journey_account
    position = submit_journey_position
    definition = position&.run && position.journey.steps_definition
    return unless definition&.user_start && position.step.key == definition.account_step&.key
    return unless page_runtime_audience == EntityAttributeAudience::ADMIN

    id = Array(position.run.records[definition.user_start.key]).last
    id && Authentication::User.find_by(id: id, customer_id: current_customer_id)
  end

  def journey_move(result)
    position = submit_journey_position
    return unless position

    run = position.run || issue_journey_run(position.journey)
    upcoming = Journeys::Advance.call(run: run, entry: result.entry, intent: params[:_intent],
                                      skip: Array(result.outcome.to_h.dig("journey", "skip")))
    if upcoming.kind == :finish
      Move.new(path: journey_finish_path(run, upcoming.step), notice: journey_finish_notice(position))
    else
      notice = t("journeys.runtime.saved_add_another") if upcoming.step.key == position.step.key
      Move.new(path: journey_step_path(upcoming.step, run), notice: notice)
    end
  end

  # Skip does not write an entry. No run, or a required step, leaves the
  # visitor on this page (`redirect_after_journey_skip`).
  def journey_skip
    position = submit_journey_position
    return unless position&.run && position.step&.optional

    upcoming = Journeys::Advance.call(run: position.run, entry: nil, intent: "skip")
    return unless upcoming

    if upcoming.kind == :finish
      Move.new(path: journey_finish_path(position.run, upcoming.step), notice: journey_finish_notice(position))
    else
      Move.new(path: journey_step_path(upcoming.step, position.run), notice: t("journeys.runtime.skipped"))
    end
  end

  def journey_finish_notice(position)
    position.journey.steps_definition.finish_message || t("journeys.runtime.completed")
  end

  def issue_journey_run(journey)
    run, @page_run_token = JourneyRun.issue!(customer_id: current_customer_id, user: page_runtime_user, session: session,
                                             journey: journey, current_step: journey.steps_definition.first_step.key)
    run
  end

  # An update step opens its page on the record its source step holds.
  def journey_step_path(step, run)
    page = Pages::ActionResolver.page_for(customer_id: current_customer_id, action_key: step.action_key, audience: page_runtime_audience)
    return post_submit_path unless page

    entry_id = Array(run.records[step.record]).last if step.update?
    run_step_surface_path(step, page, @page_run_token, entry_id: entry_id) || post_submit_path
  end

  def journey_finish_path(run, finish)
    target = finish&.target.to_h
    path =
      case target["kind"]
      when "record" then journey_record_path(run, target["step"])
      when "page" then journey_finish_page_path(target["action_key"])
      end
    path || post_submit_path
  end

  # Only where the audience can open a record: an anonymous visitor has no
  # record view, so the journey ends on the page's own landing.
  def journey_record_path(run, step_key)
    id = Array(run.records[step_key.to_s]).last
    entry = id && EntityEntry.find_by(id: id, customer_id: current_customer_id)
    return unless entry

    case page_runtime_audience
    when EntityAttributeAudience::ADMIN then admin_entity_entry_path(current_customer_id, entry.entity_id, entry.id)
    when EntityAttributeAudience::MEMBER then member_surface_path(current_customer_id, "entity_#{entry.entity_id}", entry.id)
    end
  end

  def journey_finish_page_path(action_key)
    page = Pages::ActionResolver.page_for(customer_id: current_customer_id, action_key: action_key, audience: page_runtime_audience)
    run_surface_path(page, nil) if page
  end
end
