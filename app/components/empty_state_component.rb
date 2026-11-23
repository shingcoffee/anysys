# frozen_string_literal: true

class EmptyStateComponent < ApplicationComponent
  attr_reader :title, :description, :icon_path, :action_path, :action_text

  def initialize(title:, description:, icon_path: nil, action_path: nil, action_text: nil)
    @title = title
    @description = description
    @icon_path = icon_path || default_icon_path
    @action_path = action_path
    @action_text = action_text
  end

  def render_action?
    action_path.present? && action_text.present?
  end

  private

  def default_icon_path
    "M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
  end
end
