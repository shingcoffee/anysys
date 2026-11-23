# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Utility
        class GeolocationLookupGenerator < BaseGenerator
          generator_metadata do
            description "Calculates Haversine distance between two coordinates and stores { km, miles } " \
                        "on resultVar (default location). Use this for delivery radius, event proximity, " \
                        "or pickup distance. sourceVariable and otherVariable are hashes or entity rows " \
                        "with lat/latitude and lng/lon/longitude. The platform does not configure Google " \
                        "Maps or Mapbox, so this action does not geocode an IP or address; put coordinates " \
                        "on the record first. Fails as geolocation_lookup.invalid_coordinates when a point " \
                        "is missing, and failed on unexpected errors."
            category :utility
            version "3.0.0"
            presentation icon: "M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z M15 11a3 3 0 11-6 0 3 3 0 016 0z",
                         color: "teal", single_use: false, privileged: false
          end

          config_schema do
            input :sourceVariable, required: true, example: "origin",
                  description: "Ctx path of the origin point, such as origin or venue. A hash or entity " \
                               "row with lat/latitude and lng/lon/longitude. Required."
            input :otherVariable, required: true, example: "destination",
                  description: "Ctx path of the destination point, such as destination or member_location. " \
                               "Same shape as sourceVariable. Required."
            output :resultVar, default: "location",
                   description: "Ctx variable for the result hash { km:, miles: } with four decimal places. " \
                                "Default location. Read location.km in a later Decision."
          end

          def generate_body
            attempt('"geolocation_lookup.failed"', FlowchartRuntime::Geolocation::Error) do
              [
                "location = FlowchartRuntime::Geolocation.lookup(ctx, #{lookup_args})",
                assign(:resultVar, "location"),
                "location != false"
              ]
            end
          end

          private

          def lookup_args
            [
              "source: #{read(:sourceVariable)}",
              "other: #{read(:otherVariable)}"
            ].join(", ")
          end
        end
      end
    end
  end
end
