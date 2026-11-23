# frozen_string_literal: true

module AppLogger
  module_function

  def info(message, source: nil)  = log(:info, message, source: source)
  def warn(message, source: nil)  = log(:warn, message, source: source)
  def error(message, source: nil) = log(:error, message, source: source)
  def debug(message, source: nil) = log(:debug, message, source: source)

  def log(level, message, source: nil)
    tags = build_tags(source)
    if tags.any?
      Rails.logger.tagged(*tags) { Rails.logger.public_send(level, message) }
    else
      Rails.logger.public_send(level, message)
    end
  end

  def build_tags(source)
    tags = []
    tags << "customer:#{Current.customer_id}" if Current.customer?
    tags << source if source
    tags
  end
end
