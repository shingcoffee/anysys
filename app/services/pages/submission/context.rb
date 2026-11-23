# frozen_string_literal: true

module Pages
  module Submission
    # Everything a page's flowchart receives on submit — its whole input:
    #
    #   model / page_record   the record the page writes (new on create)
    #   bound_entity          the page's entity; the flowchart has none of its own
    #   mode                  "create" or "update"
    #   params                permitted values with locked inputs ("id" on update)
    #   association_params    permitted bridge sections, written with a new page record
    #   writable_slugs        the attributes the page may set
    #   identity              permitted sign-up identity fields
    #   audience, current_user_id, current_user_role, current_person_ids
    #   source                { surface, page_id, action_key }
    #   journey               { key, step, finishing } when the submit is a journey step;
    #                         finishing is true when it ends the journey
    #   authentication, continuation, request_ip, user_agent, locale, request_id, device_type
    #
    # Secrets (identity, authentication) live only for the request.
    Context = Data.define(:page, :target, :input, :audience, :viewer, :authentication, :continuation,
                          :journey, :request) do
      def customer_id = target.record.customer_id

      def to_ctx
        record = target.record
        {
          model: record, page_record: record, bound_entity: record.entity, customer_id: customer_id,
          mode: target.mode.to_s, params: params, association_params: input.sections,
          writable_slugs: input.values.keys, identity: input.identity, audience: audience,
          current_user_id: viewer&.id, current_user_role: viewer&.primary_role_key,
          current_person_ids: current_person_ids,
          source: { "surface" => "page", "page_id" => page.id, "action_key" => page.action_key },
          journey: journey, authentication: authentication, continuation: continuation
        }.merge(request.to_h.symbolize_keys).compact
      end

      private

      def params
        record = target.record
        record.persisted? ? input.values.merge("id" => record.id.to_s) : input.values
      end

      # A signed-in user of another tenant submits as public; their own
      # tenant's person records never enter this run.
      def current_person_ids
        return {} unless viewer && viewer.customer_id.to_s == customer_id.to_s

        People::Ownership.person_entry_ids(viewer)
      end
    end
  end
end
