# frozen_string_literal: true

# Shared response contract for stateless generator I/O inspection. Callers keep
# their own namespace authorization; this concern never skips those guards.
module GeneratorIoIntrospection
  extend ActiveSupport::Concern

  private

  def render_generator_io(attribute)
    raw = params[attribute]
    pins = if raw.nil? || raw.is_a?(ActionController::Parameters)
      yield(raw.nil? ? {} : raw.to_unsafe_h.stringify_keys)
    else
      ::CodeGenerators::IoExtractor::EMPTY
    end

    render json: { inputs: pins[:inputs], outputs: pins[:outputs] }
  end
end
