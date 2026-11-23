# frozen_string_literal: true

class HelpAttachmentsFieldComponent < ApplicationComponent
  def initialize(name:, accept:, hint:, label: nil, input_id:, compact: false)
    @name = name
    @accept = accept
    @hint = hint
    @field_label = label
    @input_id = input_id
    @compact = compact
  end

  attr_reader :name, :accept, :hint, :field_label, :input_id

  def compact? = @compact

  def dropzone_classes
    if compact?
      "relative flex flex-row items-center justify-center gap-2 rounded-lg border border-dashed border-border px-3 py-2 text-center hover:border-border-strong cursor-pointer"
    else
      "relative flex flex-col items-center gap-2 rounded-lg border-2 border-dashed border-border px-4 py-6 text-center hover:border-border-strong cursor-pointer"
    end
  end

  def dropzone_aria
    return {} if field_label.blank?

    { labelledby: "#{input_id}-label" }
  end
end
