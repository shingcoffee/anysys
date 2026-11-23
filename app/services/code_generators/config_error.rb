# frozen_string_literal: true

module CodeGenerators
  ConfigError = Data.define(:field, :code, :message) do
    def to_s
      message
    end
  end
end
