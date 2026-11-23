# frozen_string_literal: true

class AlertComponent < ApplicationComponent
  TYPES = {
    success: {
      bg_class: "bg-success-subtle",
      border_class: "border-success/20",
      text_class: "text-success",
      icon_class: "text-success",
      icon_path: "M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
    },
    error: {
      bg_class: "bg-danger-subtle",
      border_class: "border-danger/20",
      text_class: "text-danger",
      icon_class: "text-danger",
      icon_path: "M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z"
    },
    warning: {
      bg_class: "bg-warning-subtle",
      border_class: "border-warning/20",
      text_class: "text-warning",
      icon_class: "text-warning",
      icon_path: "M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z"
    },
    info: {
      bg_class: "bg-info-subtle",
      border_class: "border-info/20",
      text_class: "text-info",
      icon_class: "text-info",
      icon_path: "M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z"
    }
  }.freeze

  attr_reader :message, :type

  def initialize(message:, type: :success, auto_dismiss: false)
    @message = message
    @type = type.to_sym
    @auto_dismiss = auto_dismiss
  end

  def auto_dismiss?
    @auto_dismiss
  end

  def render?
    message.present?
  end

  def config
    TYPES.fetch(type, TYPES[:info])
  end

  def bg_class
    config[:bg_class]
  end

  def border_class
    config[:border_class]
  end

  def text_class
    config[:text_class]
  end

  def icon_class
    config[:icon_class]
  end

  def icon_path
    config[:icon_path]
  end
end
