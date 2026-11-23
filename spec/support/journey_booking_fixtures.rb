# frozen_string_literal: true

# A booking workflow split into journeys linked by the booking's status:
# admins request a booking (a new one starts Requested), review Requested
# bookings (the reviewer picks Approved or Declined on the form) and take
# payment for Approved ones (Paid once the payment succeeds). Expects
# `customer`.
RSpec.shared_context "booking journeys" do
  let(:booking_status) do
    { "name" => "Status", "name_slug" => "status", "type" => "String", "html_type" => "select",
      "config" => { "source" => "manual", "options" => [
        { "label" => "Requested", "value" => "requested", "default" => true },
        { "label" => "Approved", "value" => "approved" }, { "label" => "Declined", "value" => "declined" },
        { "label" => "Paid", "value" => "paid" }
      ] },
      "lifecycle" => { "transitions" => [
        { "from" => "requested", "to" => "approved", "by" => %w[admin] },
        { "from" => "requested", "to" => "declined", "by" => %w[admin] },
        { "from" => "approved", "to" => "paid", "by" => %w[system] }
      ] } }
  end
  let(:booking) do
    create(:entity, customer: customer, name: "Booking", display_label: "Booking", property_schema: [
      { "name" => "Title", "name_slug" => "title", "type" => "String", "html_type" => "text" }, booking_status
    ].to_json)
  end
  let(:booking_domain) { create(:entity_domain, customer: customer) }

  let!(:request_page) { booking_page("booking_new", %w[title], %w[create], name: "Request form") }
  let!(:review_page) { booking_page("booking_review", %w[status], %w[update], name: "Review form") }
  let!(:pay_page) do
    booking_page("booking_pay", %w[title], %w[update], name: "Pay form").tap do |page|
      payment = { "amount" => "10.00", "subject" => "\"Booking\"", "paidFields" => [{ "key" => "status", "value" => "paid" }] }
      bind_page_flowchart(page, steps: [{ "action" => "request_payment", "config" => payment }], body: "true")
      page.reload
    end
  end

  let!(:request_journey) do
    booking_journey("request_booking", "Request a booking", [
      { "key" => "booking", "kind" => "create", "action_key" => "booking_new", "label" => "Booking details" },
      { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "booking" } }
    ])
  end
  let!(:review_journey) { record_journey("review_booking", "Review a booking", "requested", "booking_review", "review") }
  let!(:pay_journey) { record_journey("pay_booking", "Pay for a booking", "approved", "booking_pay", "payment") }

  def booking_page(action_key, fields, modes, **attributes)
    Current.set(customer: customer) do
      create(:page, customer: customer, entity: booking, launched: true, action_key: action_key, **attributes, configuration: {
        form_settings: { modes: modes },
        metadata: { entity_id: booking.id, entity_name: booking.name },
        pages: [{ "id" => "page_1", "fields" => fields.map { |slug| { "id" => "f_#{slug}", "property_slug" => slug, "source" => "entity", "html_type" => "text" } } }]
      }.to_json)
    end
  end

  def booking_journey(key, name, steps)
    create(:journey, customer: customer, entity_domain: booking_domain, key: key, name: name, definition: { "steps" => steps }.to_json)
  end

  def record_journey(key, name, state, action_key, step_key)
    booking_journey(key, name, [
      { "key" => "record", "kind" => "record", "entity_id" => booking.id.to_s, "when" => { "field" => "status", "in" => [state] } },
      { "key" => step_key, "kind" => "update", "action_key" => action_key, "record" => "record" },
      { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "record" } }
    ])
  end
end
