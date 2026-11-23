# frozen_string_literal: true

require "toml-rb"

module FlowchartRuntime
  # FlowchartRuntime::Toml
  #
  # Thin wrapper around toml-rb for flowchart parse_data TOML step generators.
  module Toml
    class Error < StandardError; end

    module_function

    # @param string [String]
    # @return [Hash]
    # @raise  [FlowchartRuntime::Toml::Error]
    def parse(string)
      TomlRB.parse(string.to_s)
    rescue TomlRB::Error => e
      raise Error, e.message
    end

    # @param hash [Hash]
    # @return [String]
    # @raise  [FlowchartRuntime::Toml::Error]
    def generate(hash)
      raise Error, "input must be a hash" unless hash.is_a?(Hash)

      TomlRB.dump(hash)
    rescue TomlRB::Error => e
      raise Error, e.message
    end
  end
end
