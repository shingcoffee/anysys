# frozen_string_literal: true

module Help
  Result = Struct.new(:success?, :model, :errors, :messages, keyword_init: true)
end
