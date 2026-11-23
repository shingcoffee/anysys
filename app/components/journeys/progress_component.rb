# frozen_string_literal: true

module Journeys
  # A compact stepper above a journey step's form: the current step's name and
  # "Step 2 of 3", then one numbered marker per step (a check once done). It
  # mirrors the form wizard's indicators at a smaller size and keeps to the
  # neutral palette, so it sits on any page theme. A step without its own
  # label is named after the page the viewer's audience gets for it; a user
  # step (the account an admin creates first) is named as such.
  class ProgressComponent < ApplicationComponent
    CHECK = "M5 13l4 4L19 7"

    attr_reader :steps, :current_index

    def initialize(journey:, current_key:)
      @journey = journey
      @steps = journey.steps_definition.progress_steps
      @current_index = @steps.index { |step| step.key == current_key.to_s } || 0
    end

    def summary = t("journeys.runtime.step_of", current: current_index + 1, total: steps.size)
    def current_label = steps[current_index] && label_for(steps[current_index])
    def current_optional? = steps[current_index]&.optional == true

    def label_for(step)
      step.label.presence || (step.user? ? t("journeys.runtime.user_step") : page_names[step.action_key].to_s)
    end

    def state(index)
      if index < current_index then :done
      elsif index == current_index then :current
      else :upcoming
      end
    end

    def marker_classes(index)
      case state(index)
      when :done then "bg-slate-900 text-white"
      when :current then "bg-white text-slate-900 ring-2 ring-inset ring-slate-900"
      else "bg-slate-100 text-slate-400"
      end
    end

    def connector_classes(index) = index < current_index ? "bg-slate-900" : "bg-slate-200"

    private

    def page_names
      @page_names ||= Pages::ActionResolver.pages_for(
        customer_id: @journey.customer_id, action_keys: steps.reject { |step| step.label.present? || step.user? }.map(&:action_key),
        audience: EntityAttributeAudience.for_user(Current.user, customer_id: @journey.customer_id)
      ).transform_values(&:name)
    end
  end
end
