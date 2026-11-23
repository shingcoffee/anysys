# frozen_string_literal: true

# A small venue-booking sub-system: the requirements brief, the business
# flows the journey stage designs from it, and the create_entity arguments
# the entity stage writes for those flows. Staff record bookings with their
# guests, then approve or decline the requested ones.
module SubsystemBuildFixtures
  def venue_brief(**overrides)
    {
      "domain" => { "name" => "Venue Bookings", "description" => "Staff book the club's venues." },
      "summary" => "Staff record venue bookings with their guests, then approve or decline each request.",
      "people" => [{ "name" => "Bookings staff", "audience" => "admin", "description" => "Record and review bookings." }],
      "scenarios" => [{ "name" => "Staff book a venue", "actor" => "Bookings staff",
                        "steps" => ["Record the booking and its guests", "Approve or decline it"],
                        "exceptions" => ["The venue is already booked that day: the booking is refused"] }],
      "rules" => ["A venue takes one booking a day."],
      "values" => [{ "label" => "Bookings team email", "value" => "bookings@club.test" }]
    }.merge(overrides.stringify_keys)
  end

  def venue_flows
    {
      "objects" => [
        { "name" => "Venue", "purpose" => "A room the club rents out." },
        { "name" => "Booking", "purpose" => "One booking of a venue on a date.",
          "status" => { "field" => "Booking status", "states" => %w[Requested Approved Declined], "initial" => "Requested" } },
        { "name" => "Guest", "purpose" => "One person coming to a booking." }
      ],
      "journeys" => [
        { "key" => "record_booking", "name" => "Record a booking", "audience" => "admin",
          "steps" => [
            { "key" => "booking", "kind" => "create", "object" => "Booking", "label" => "Booking details",
              "fields" => ["Venue", "Booking date"], "processing" => "Email the bookings team the venue and date.",
              "values" => [{ "label" => "Bookings team email", "value" => "bookings@club.test" }] },
            { "key" => "guests", "kind" => "add", "object" => "Guest", "label" => "Guests", "parent" => "booking",
              "fields" => ["Guest name"], "optional" => true }
          ],
          "finish_message" => "Booking recorded." },
        { "key" => "review_booking", "name" => "Review a booking", "audience" => "admin",
          "start" => { "object" => "Booking", "status_in" => ["Requested"] },
          "steps" => [
            { "key" => "review", "kind" => "update", "object" => "Booking", "label" => "Approve or decline", "edits" => "start",
              "fields" => ["Booking status"], "status_choices" => %w[Approved Declined] }
          ] }
      ],
      "not_covered" => ["Reminder emails before the booking"]
    }
  end

  def venue_entities(domain: "Venue Bookings")
    {
      "domain" => domain,
      "entities" => [
        { "name" => "Venue", "attributes" => [{ "name" => "Venue name", "html_type" => "text", "rules" => [{ "type" => "presence" }] }] },
        { "name" => "Booking", "attributes" => [
          { "name" => "Venue", "html_type" => "select", "options" => { "source" => "entity_entries", "entity" => "Venue", "label_field" => "venue_name" } },
          { "name" => "Booking date", "html_type" => "date" },
          { "name" => "Booking status", "html_type" => "select",
            "options" => { "source" => "static", "values" => [{ "label" => "Requested", "default" => true }, { "label" => "Approved" }, { "label" => "Declined" }] },
            "lifecycle" => { "transitions" => [{ "from" => "Requested", "to" => "Approved", "by" => ["admin"] },
                                               { "from" => "Requested", "to" => "Declined", "by" => ["admin"] }] } }
        ] },
        { "name" => "Guest", "attributes" => [
          { "name" => "Guest name", "html_type" => "text" },
          { "name" => "Booking", "html_type" => "select", "options" => { "source" => "entity_entries", "entity" => "Booking", "label_field" => "booking_date" } }
        ] }
      ]
    }
  end
end

RSpec.configure { |config| config.include SubsystemBuildFixtures }
