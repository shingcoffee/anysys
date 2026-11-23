# frozen_string_literal: true

module Admin
  module Settings
    class SectionComponent < ApplicationComponent
      # `actions` sits right of the header title (toolbar buttons, filters);
      # `footer` is a bordered bar under the body (form submit row).
      renders_one :actions
      renders_one :footer

      attr_reader :title, :description, :id, :flush

      def initialize(title: nil, description: nil, id: nil, flush: false)
        @title = title
        @description = description
        @id = id
        @flush = flush
      end

      def flush?
        flush
      end

      def header?
        title.present? || description.present? || actions?
      end
    end
  end
end
