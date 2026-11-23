# frozen_string_literal: true

module AccessPoints
  # Value object representing a single access point in the catalog.
  # Immutable; enforces type constraints at initialization.
  class Descriptor
    attr_reader :subject_type, :subject_key, :subject_id, :actions,
                :group_key, :label, :description

    def initialize(subject_type:, subject_key:, subject_id:, actions:,
                   group_key:, label:, description: nil)
      raise ArgumentError, "subject_type must be a String" unless subject_type.is_a?(String)
      raise ArgumentError, "subject_key must be a String or nil" unless subject_key.nil? || subject_key.is_a?(String)
      raise ArgumentError, "subject_id must be an Integer or nil" unless subject_id.nil? || subject_id.is_a?(Integer)
      raise ArgumentError, "actions must be an Array of Symbols" unless actions.is_a?(Array) && actions.all? { |a| a.is_a?(Symbol) }
      raise ArgumentError, "group_key must be a String" unless group_key.is_a?(String)
      raise ArgumentError, "label must be a String" unless label.is_a?(String)
      raise ArgumentError, "description must be a String or nil" unless description.nil? || description.is_a?(String)

      @subject_type = subject_type
      @subject_key  = subject_key
      @subject_id   = subject_id
      @actions      = actions.freeze
      @group_key    = group_key
      @label        = label
      @description  = description

      freeze
    end
  end
end
