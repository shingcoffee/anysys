# frozen_string_literal: true

require "delegate"

module FlowchartRuntime
  # Read-only execution facade over the live version: the launched one, never
  # a draft saved above it. A tenant override is compiled from its pinned
  # resolved definition, into ActivityClassBuilder's anonymous namespace;
  # neither the parent artifact nor any version/head is written.
  class RuntimeFlowchart < SimpleDelegator
    include Flowchart::StepActions

    def initialize(record, preview: false)
      super(record)
      version = record.live_version
      payload = version&.content&.payload
      @configuration = (!preview && payload.present? ? JSON.parse(payload) : record.configuration_json) || {}
      @override = version.present? && version.id != record.published_version&.id
    end

    def runtime_execution? = true
    def configuration_json = @configuration
    def elements = Array(@configuration["elements"])
    def connections = Array(@configuration["connections"])
    def metadata = @configuration["metadata"] || {}

    def activity
      return __getobj__.activity unless @override
      return @runtime_activity if defined?(@runtime_activity)
      @runtime_activity = RuntimeGenerator.new(self).generate
    end

    class RuntimeGenerator < ActivityGenerator
      private

      def load_subflow_for_current_owner(id)
        record = Flowchart.accessible.launched.find_by(id: id)
        record && RuntimeFlowchart.new(record)
      end
    end
  end
end
