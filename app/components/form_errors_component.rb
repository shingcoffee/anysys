# frozen_string_literal: true

class FormErrorsComponent < ApplicationComponent
  attr_reader :resource

  def initialize(resource:)
    @resource = resource
  end

  def render?
    resource.present? && resource.errors.any?
  end

  def error_count
    resource.errors.count
  end

  def model_name
    resource.model_name.human.downcase
  end

  def error_messages
    resource.errors.full_messages
  end

  def header_text
    I18n.t("chrome.form_errors.header", count: error_count, model: model_name)
  end
end
