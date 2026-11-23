# frozen_string_literal: true

module Platform
  module CodeGenerators
    class PlaygroundResultComponent < ApplicationComponent
      IO_TONES = { input: "text-warning border-warning/30", output: "text-success border-success/30" }.freeze

      def initialize(result: nil, error: nil)
        @result = result || {}
        @error = error
      end

      private

      attr_reader :error

      def validation_errors
        Array(@result[:validation_errors]).map(&:to_s)
      end

      def code
        @result[:code]
      end

      def io_groups
        { input: Array(@result[:inputs]), output: Array(@result[:outputs]) }
      end
    end
  end
end
