# frozen_string_literal: true

# ActivityClassBuilder
#
# Shared concern for building Trailblazer Activity classes from generated
# activity code strings. Used by both ActivityTracer and ActivityDiagramGenerator.
#
# Model and contract classes are loaded dynamically into an isolated namespace
# using DynamicClassLoader before the activity code is evaluated. This avoids
# including class definitions in the generated code and prevents issues with
# require statements for external dependencies like reform.
#
# Subflow activity classes are also loaded recursively to support Subprocess steps.
#
module ActivityClassBuilder
  extend ActiveSupport::Concern

  included do
    include Loggable
  end

  # Builds a Trailblazer::Activity::Railway subclass from activity code string.
  #
  # Uses DynamicClassLoader to load model/contract classes into an isolated
  # namespace before evaluating the activity code. This allows the activity
  # to reference these classes without requiring their definitions to be
  # included in the code string.
  #
  # Also loads subflow activity classes recursively for Subprocess support.
  #
  # @param activity_code [String] the generated activity code
  # @param entity [Entity, nil] the run's bound entity (optional, for loading model/contract);
  #   subflows share it
  # @param flowchart [Flowchart, nil] the flowchart (optional, for loading subflow activities)
  # @return [Class, nil] the activity class or nil if evaluation fails
  def build_activity_class(activity_code, entity: nil, flowchart: nil)
    return nil if activity_code.blank?

    namespace = Module.new

    # Load model/contract classes into namespace using metaprogramming
    load_dynamic_classes(namespace, entity)

    # Load subflow activity classes into namespace for Subprocess support
    load_subflow_activities(namespace, flowchart) if flowchart

    # Capture constants before loading the main activity
    existing_constants = namespace.constants.to_set

    # Evaluate the activity code in the namespace
    namespace.module_eval(activity_code)

    # Find the NEWLY defined activity class (not pre-existing subflow classes)
    new_constants = namespace.constants - existing_constants.to_a
    new_constants
      .map { |c| namespace.const_get(c) }
      .find { |k| trailblazer_activity?(k) }
  rescue SyntaxError, StandardError => e
    log_error "Failed to build activity class - #{e.class}: #{e.message}"
    nil
  end

  # Derives a human-readable label from a Trailblazer node ID.
  def derive_node_label(node_id)
    id = node_id.to_s
    key = helper_trace_key(id)
    return I18n.t(key) if key

    id.split("_").map(&:capitalize).join(" ")
  end

  private

  def helper_trace_key(node_id)
    return "flowchart_elements.trace.start" if node_id == "Start.default"

    if node_id.start_with?("End.")
      semantic = node_id.split(".", 2).last
      key = "flowchart_elements.trace.#{semantic}"
      return key if I18n.exists?(key)
    end

    key = "flowchart_elements.trace.#{node_id}"
    I18n.exists?(key) ? key : nil
  end

  # Load model/contract classes dynamically into namespace using DynamicClassLoader.
  # This uses Ruby metaprogramming to define classes without requiring their
  # source code to be part of the activity code string.
  def load_dynamic_classes(namespace, entity)
    loader = DynamicClassLoader.new(entity)
    loader.load_into(namespace)
  rescue StandardError => e
    log_warn "Failed to load dynamic classes - #{e.message}"
    # Continue without loaded classes - activity may still work for introspection
  end

  # Load subflow activity classes into namespace for Subprocess support.
  # Finds all subflow elements in the flowchart and builds their activity classes.
  def load_subflow_activities(namespace, flowchart, loaded_ids: Set.new)
    return if flowchart.nil?
    if flowchart.respond_to?(:runtime_execution?) && flowchart.runtime_execution?
      return load_runtime_subflow_activities(namespace, flowchart, loaded_ids: loaded_ids)
    end

    # Prevent infinite recursion
    return if loaded_ids.include?(flowchart.id)

    loaded_ids.add(flowchart.id)

    # Find all subflow elements in the flowchart
    subflow_elements = flowchart.elements.select { |el| el["type"] == "subflow" }

    subflow_elements.each do |subflow_element|
      flowchart_id = subflow_element.dig("properties", "flowchartId")
      next unless flowchart_id

      subflow_flowchart = ActivityGenerator::SubflowResolver.visible_to(flowchart, flowchart_id)
      next unless subflow_flowchart&.activity.present?
      next if loaded_ids.include?(subflow_flowchart.id)

      # Recursively load nested subflow activities first
      load_subflow_activities(namespace, subflow_flowchart, loaded_ids: loaded_ids)

      # Build and define the subflow activity class in the namespace
      begin
        namespace.module_eval(subflow_flowchart.activity)
      rescue StandardError => e
        log_warn "Failed to load subflow activity #{subflow_flowchart.name} - #{e.message}"
      end
    end
  end

  # Public/member execution only: fail closed on inaccessible, offline or
  # cyclic children and resolve each child's tenant-specific definition.
  def load_runtime_subflow_activities(namespace, flowchart, loaded_ids:, active_ids: Set.new)
    if active_ids.include?(flowchart.id) || active_ids.size >= 32
      raise ActiveRecord::RecordNotFound, I18n.t("common.errors.dynamic.flowchart_not_found")
    end
    return if loaded_ids.include?(flowchart.id)

    active_ids.add(flowchart.id)
    flowchart.elements.select { |element| element["type"] == "subflow" }.each do |element|
      record = Flowchart.accessible.launched.find_by(id: element.dig("properties", "flowchartId"))
      raise ActiveRecord::RecordNotFound, I18n.t("common.errors.dynamic.flowchart_not_found") unless record
      child = FlowchartRuntime::RuntimeFlowchart.new(record)
      raise ActiveRecord::RecordNotFound, I18n.t("common.errors.dynamic.activity_not_generated") if child.activity.blank?
      next if loaded_ids.include?(child.id)

      load_runtime_subflow_activities(namespace, child, loaded_ids: loaded_ids, active_ids: active_ids)
      namespace.module_eval(child.activity)
    end
    loaded_ids.add(flowchart.id)
  ensure
    active_ids.delete(flowchart.id)
  end

  def trailblazer_activity?(klass)
    klass < Trailblazer::Activity::Railway
  rescue TypeError
    false
  end
end
