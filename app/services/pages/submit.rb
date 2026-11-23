# frozen_string_literal: true

module Pages
  # One page submission. The page is only the trust boundary: it picks the
  # record (Submission::Target), permits what the viewer may send
  # (Submission::Input), and hands both to the flowchart the page is bound to,
  # which owns every business rule (FlowchartRuntime::PageRun). A module
  # handoff the flowchart asks for begins inside the same savepoint, so its
  # refusal rolls the record back.
  #
  # The controller owns HTTP: where the visitor goes next, and the flash.
  class Submit
    # +status+ is exactly one of:
    #   :refused  — the page doesn't take this submission (#http_status)
    #   :rejected — the input was refused before anything ran (#message)
    #   :offline  — the page has no live processing (#message)
    #   :failed   — the flowchart refused and everything rolled back:
    #               #field_errors ({ slug => [message] }) for fields on the
    #               page, #message for the rest, #values what was typed
    #   :success  — #entry is the page record (nil when none is handed over),
    #               #outcome the flowchart's, #handed_off whether a module
    #               invocation began
    Result = Data.define(:status, :http_status, :message, :entry, :outcome, :handed_off, :field_errors, :values) do
      def initialize(status:, http_status: nil, message: nil, entry: nil, outcome: nil, handed_off: nil,
                     field_errors: nil, values: nil)
        super
      end

      def success? = status == :success
    end

    def self.call(...)
      new(...).call
    end

    # +viewer+ is the tenant viewer (nil for anonymous visitors and users of
    # other tenants); +bindings+ the page's resolved locked inputs; +journey+
    # ({ "key", "step" }) the step this submit is, if any; +account+ the user
    # a journey's user step created, whom the new record is linked to;
    # +journey_record_id+ the record the run's current update step edits,
    # which a member may then change (Submission::Target).
    def initialize(page:, params:, customer:, viewer:, bindings:, journey:, authentication:, user_agent:, session:, account: nil,
                   journey_record_id: nil)
      @page = page
      @params = params
      @customer = customer
      @viewer = viewer
      @bindings = bindings.to_h
      @journey = journey
      @account = account
      @journey_record_id = journey_record_id
      @authentication = authentication
      @user_agent = user_agent
      @session = session
      @audience = EntityAttributeAudience.for_user(viewer, customer_id: customer.id)
    end

    def call
      FeatureModules::Invocation.with_submission(session: @session) { submit }
    end

    private

    def submit
      return refused(:not_found, "common.errors.dynamic.entity_required") unless entity
      if FormParams.base_submission?(@params)
        return refused(:unprocessable_entity, "common.errors.dynamic.base_model_submission_not_supported")
      end

      target = resolve_target
      return refused(target.http_status, target.message_key) if target.is_a?(Submission::Target::Refusal)

      input = permit_input(target)
      return rejected(input.error) if input.rejected?

      flowchart = @page.flowchart
      return offline unless flowchart&.launched?

      run = FlowchartRuntime::PageRun.call(flowchart: flowchart, context: context_for(target, input)) do |entry, outcome|
        link_account(entry) if target.create?
        hand_off(entry, outcome)
      end
      run.ok? ? succeeded(run) : failed(run, input)
    end

    def entity
      @page.entity
    end

    def resolve_target
      Submission::Target.resolve(page: @page, entity: entity, entry_id: @params[:entry_id], audience: @audience,
                                 viewer: @viewer, customer_id: @customer.id, journey_record_id: @journey_record_id)
    end

    def permit_input(target)
      Submission::Input.permit(page: @page, entity: entity, params: @params, bindings: @bindings,
                               audience: @audience, viewer: @viewer, customer_id: @customer.id, create: target.create?)
    end

    def context_for(target, input)
      Submission::Context.new(
        page: @page, target: target, input: input, audience: @audience, viewer: @viewer,
        authentication: @authentication, continuation: Continuation.verify(@params[:_continuation]) || journey_continuation,
        journey: @journey, request: request_metadata
      )
    end

    # A public sign-up journey that finishes on a page continues there once
    # the visitor confirms their email (register_member parks it on the claim).
    def journey_continuation
      return unless @journey && @audience == EntityAttributeAudience::PUBLIC

      target = Journey.find_by(customer_id: @customer.id, key: @journey["key"])&.steps_definition&.finish&.target.to_h
      action_key = target["action_key"].to_s
      { action_key: action_key, prefill: {} } if target["kind"] == "page" && action_key.match?(PageVisibility::ACTION_KEY)
    end

    def link_account(entry)
      return unless @account && entry

      result = People::Link.link!(entry: entry, user_id: @account.id, actor: @viewer)
      raise FlowchartRuntime::PageRun::Refused, result.errors.to_sentence unless result.success?
    end

    def request_metadata
      { request_ip: Current.ip_address, user_agent: @user_agent, locale: I18n.locale.to_s,
        request_id: Current.request_id, device_type: DeviceType.call(@user_agent) }
    end

    def hand_off(entry, outcome)
      FeatureModules::PageHandoff.call(session: @session, customer: @customer, page: @page,
                                       entity_entry: entry, outcome: outcome, audience: @audience)
    end

    def refused(http_status, message_key)
      Result.new(status: :refused, http_status: http_status, message: I18n.t(message_key))
    end

    def rejected(message)
      Result.new(status: :rejected, http_status: :unprocessable_entity, message: message)
    end

    def offline
      Result.new(status: :offline, http_status: :service_unavailable,
                 message: I18n.t("maint_core.errors.page_launch.submission_process_offline"))
    end

    def succeeded(run)
      Result.new(status: :success, entry: run.entry, outcome: run.outcome, handed_off: run.handed_off)
    end

    # Errors of fields this page shows go beside them; the rest, and errors of
    # fields it doesn't show, form the message.
    def failed(run, input)
      shown = FormParams.primary_slugs(@page)
      inline, hidden = run.field_errors.partition { |error| shown.include?(error.field) }
      covered = inline.map(&:full_message)
      remaining = run.errors.reject { |message| covered.include?(message) } + hidden.map(&:full_message)

      Result.new(status: :failed, message: remaining.uniq.to_sentence.presence,
                 field_errors: inline.group_by(&:field).transform_values { |errors| errors.map(&:message).uniq },
                 values: input.retry_values)
    end
  end
end
