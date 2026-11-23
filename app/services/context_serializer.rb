# frozen_string_literal: true

# ContextSerializer
#
# Converts complex Ruby objects to loggable/serializable format.
# Used by services that need to log or serialize
# activity context containing ActiveRecord objects, Classes, Procs, etc.
#
# @example
#   serialized = ContextSerializer.serialize(user)
#   # => { _type: "User", id: 1, attributes: { name: "John", email: "..." } }
#
class ContextSerializer
  class << self
    # Serialize a value to a loggable/JSON-safe format
    #
    # @param value [Object] the value to serialize
    # @return [Object] serialized value
    def serialize(value)
      case value
      when Hash
        serialize_hash(value)
      when Array
        serialize_array(value)
      when ActiveRecord::Base
        serialize_record(value)
      when Class
        serialize_class(value)
      when Symbol
        value.to_s
      when Proc, Method
        serialize_callable(value)
      when ActionDispatch::Request
        serialize_request(value)
      else
        value
      end
    end

    private

    def serialize_hash(hash)
      hash.transform_values { |v| serialize(v) }
    end

    def serialize_array(array)
      array.map { |v| serialize(v) }
    end

    def serialize_record(record)
      {
        _type: record.class.name,
        id: record.id,
        attributes: record.attributes.except("activity", "configuration", "property_schema", "data")
      }
    end

    def serialize_class(klass)
      { _type: "Class", name: klass.name }
    end

    def serialize_callable(callable)
      { _type: callable.class.name, source: callable.to_s }
    end

    def serialize_request(request)
      { _type: "Request", method: request.method, path: request.path }
    end
  end
end
