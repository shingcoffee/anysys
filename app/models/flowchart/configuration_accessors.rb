# frozen_string_literal: true

# Read-only helpers that project structured data out of the JSON configuration
# blob. All methods delegate to +configuration_json+ (provided by the
# JsonSerializable concern) and are side-effect-free.
module Flowchart::ConfigurationAccessors
  extend ActiveSupport::Concern
  include Flowchart::StepActions

  def elements
    configuration_json&.dig("elements") || []
  end

  def connections
    configuration_json&.dig("connections") || []
  end

  def metadata
    configuration_json&.dig("metadata") || {}
  end

  def canvas_size
    metadata.dig("canvas") || { "width" => 1200, "height" => 800 }
  end
end
