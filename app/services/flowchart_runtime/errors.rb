# frozen_string_literal: true

module FlowchartRuntime
  # Collects unique, submitter-facing error messages from a finished activity ctx.
  # Child-flow messages already in ctx[:errors] come first; then every top-level
  # value that exposes errors.full_messages (Reform contracts, Active Model
  # records).
  module Errors
    # One message tied to an attribute slug. +full_message+ is the text the
    # same error has in #collect, so a caller can tell field errors apart
    # from the rest.
    Field = Data.define(:field, :message, :full_message)

    module_function

    def collect(ctx)
      existing = Array(ctx[:errors]).grep(String).reject(&:blank?)
      extras = ctx.each_with_object([]) do |(key, value), messages|
        next if key == :errors
        next unless value.respond_to?(:errors)

        errors = value.errors
        next unless errors.respond_to?(:full_messages)

        messages.concat(Array(errors.full_messages).map { |message| message.to_s })
      end
      (existing + extras).uniq
    end

    # Field errors from "Fail with error" style steps (error_details with a
    # field) and from every top-level value whose errors are keyed by attribute.
    def fields(ctx)
      detailed = Array(ctx[:error_details]).grep(Hash).filter_map do |detail|
        field = detail["field"].to_s
        message = detail["message"].to_s
        next unless field.present? && message.present?

        Field.new(field: field, message: message, full_message: detail["full_message"].presence || message)
      end
      keyed = ctx.each_with_object([]) do |(key, value), found|
        next if key == :errors || !value.respond_to?(:errors)

        found.concat(of(value.errors))
      end
      (detailed + keyed).uniq
    end

    # Field errors of one Active Model / Reform errors object; :base is not a field.
    def of(errors)
      messages = errors.respond_to?(:messages) ? errors.messages : nil
      return [] unless messages.respond_to?(:each_pair)

      messages.each_pair.flat_map do |attribute, texts|
        next [] if attribute.to_s == "base"

        full = errors.respond_to?(:full_messages_for) ? Array(errors.full_messages_for(attribute)) : []
        Array(texts).each_with_index.map do |text, index|
          Field.new(field: attribute.to_s, message: text.to_s, full_message: (full[index] || text).to_s)
        end
      end
    end
  end
end
