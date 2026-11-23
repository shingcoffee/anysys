# frozen_string_literal: true

module Loggable
  extend ActiveSupport::Concern

  private

  def log_info(message)  = AppLogger.info(message, source: log_source)
  def log_warn(message)  = AppLogger.warn(message, source: log_source)
  def log_error(message) = AppLogger.error(message, source: log_source)
  def log_debug(message) = AppLogger.debug(message, source: log_source)

  def log_source
    self.class.name&.demodulize || "Anonymous"
  end
end
