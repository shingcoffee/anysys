# frozen_string_literal: true

module Journeys
  # A journey that opens with a user step runs on Authentication › Users › New:
  # the admin creates the account there, then the run continues on the page
  # whose new person record is linked to that account
  # (JourneyNavigation#journey_account). Launch checks keep such journeys for
  # admins only, with at most one live per person page.
  module UserStart
    ADMIN = EntityAttributeAudience::ADMIN

    # +page+: the admin page the run continues on once the account exists.
    Start = Data.define(:journey, :page)

    module_function

    # The launched journey that opens with a user step before +page+.
    def for_page(page:, customer_id:)
      return if page.action_key.blank?

      Journey.launched.where(customer_id: customer_id).for_any_audience([ADMIN])
             .opening_with_user_on(page.action_key).order(:id).first
    end

    # The journey `key` names when it is live for admins, or a draft the
    # platform owner previews, and its account step has a page.
    def find(key:, customer_id:, viewer:)
      return if key.blank?

      journey = Journey.find_by(customer_id: customer_id, key: key.to_s)
      step = journey&.steps_definition&.account_step
      return unless step && ((journey.launched? && journey.visible_to?(ADMIN)) || JourneyVisibility.allowed?(viewer))

      page = Pages::ActionResolver.page_for(customer_id: customer_id, action_key: step.action_key, audience: ADMIN)
      Start.new(journey: journey, page: page) if page
    end

    # Issues the run, holding the new account under the user step, and
    # returns its token.
    def begin!(start:, account:, viewer:, session:)
      definition = start.journey.steps_definition
      _run, token = JourneyRun.issue!(customer_id: start.journey.customer_id, user: viewer, session: session,
                                      journey: start.journey, current_step: definition.account_step.key,
                                      state: { "records" => { definition.user_start.key => [account.id.to_s] } })
      token
    end
  end
end
