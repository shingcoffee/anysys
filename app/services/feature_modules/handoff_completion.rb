# frozen_string_literal: true

require "ostruct"

module FeatureModules
  # Completes a page → module handoff whose contract declares user_fillable
  # inputs: the end user fills the gaps on the module's entry page, pre-filled
  # from whatever the author mapped. The security boundary lives here — only
  # user_fillable field names are accepted from the submitted params, so a
  # crafted request can never overwrite an author_only value (e.g. amount).
  class HandoffCompletion
    Result = Struct.new(:ok, :input, :errors, keyword_init: true) do
      def ok? = ok
    end

    class << self
      # The user_fillable fields to render on the entry page.
      def user_fillable_fields(registration)
        Array(registration.input_contract_fields).select(&:user_fillable?)
      end

      # Should the module show an entry step at all? False → no fillable fields,
      # so the module keeps its immediate (legacy) path.
      def needs_completion?(registration)
        user_fillable_fields(registration).any?
      end

      # Filter → cast → merge over the invocation input → re-validate.
      # `invocation` is the already-resolved invocation (its [:input] is the
      # author-mapped, casted payload). Persists the merged input back to the
      # live invocation via Invocation.update_input!. The merged input is
      # returned so the caller can materialize without a session round-trip.
      def complete!(session:, invocation:, user_params:, registration:)
        fields         = Array(registration.input_contract_fields)
        fillable_names = user_fillable_fields(registration).map(&:name)

        # Read only the declared scalar fields even when Rails params are
        # unpermitted. A nested hash/array must never satisfy string presence.
        submitted = user_params.is_a?(Hash) || user_params.is_a?(ActionController::Parameters) ? user_params : {}
        permitted = fillable_names.each_with_object({}) do |name, out|
          next unless submitted.key?(name) || submitted.key?(name.to_sym)
          value = submitted.key?(name) ? submitted[name] : submitted[name.to_sym]
          out[name] = value if [NilClass, String, Numeric, TrueClass, FalseClass].any? { |type| value.is_a?(type) }
        end
        casted    = FeatureModules::InputCaster.call(input: permitted, fields: fields)

        existing = ((invocation && invocation[:input]) || {}).to_h.symbolize_keys
        merged   = existing.merge(casted.symbolize_keys)

        contract = registration.input_contract_class.new(OpenStruct.new)
        unless contract.validate(merged.stringify_keys)
          return Result.new(ok: false, input: nil, errors: contract.errors)
        end

        FeatureModules::Invocation.update_input!(session: session, input: merged)
        Result.new(ok: true, input: merged, errors: nil)
      end
    end
  end
end
