# frozen_string_literal: true

module Pages
  # The errors a refused submission left on one page field, under its input.
  class FieldErrorComponent < ApplicationComponent
    attr_reader :messages

    def initialize(messages:)
      @messages = Array(messages).map(&:to_s).reject(&:blank?).uniq
    end

    def render? = messages.any?
  end
end
