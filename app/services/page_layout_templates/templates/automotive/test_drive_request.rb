# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Automotive
      module TestDriveRequest
        DEFINITION = {
          key: "test_drive_request",
          name: "Test Drive Request",
          description: "Schedule a test drive with vehicle selection and license verification",
          category: "automotive",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Contact Info" }],
            [{ type: :input, width: "half", label: "First Name" }, { type: :input, width: "half", label: "Last Name" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "full", label: "Home Address" }],
            [{ type: :input, width: "half", label: "Driver's License Number" }, { type: :select, width: "half", label: "License State" }],
            [{ type: :divider }],
            [{ type: :section, label: "Vehicle & Schedule" }],
            [{ type: :select, width: "third", label: "Make" }, { type: :select, width: "third", label: "Model" }, { type: :select, width: "third", label: "Year" }],
            [{ type: :input, width: "half", label: "Trim Level / Package (if known)" }, { type: :input, width: "half", label: "Stock # or VIN (if known)" }],
            [{ type: :radio, width: "full", label: "New or Pre-Owned?" }],
            [{ type: :select, width: "half", label: "Preferred Exterior Color" }, { type: :select, width: "half", label: "Preferred Interior Color" }],
            [{ type: :checkbox, width: "full", label: "Features of Interest (4WD/AWD, Sunroof, Leather, Navigation, Safety Tech, Towing Package, Hybrid/Electric)" }],
            [{ type: :date, width: "half", label: "Preferred Date (1st Choice)" }, { type: :select, width: "half", label: "Preferred Time (1st Choice)" }],
            [{ type: :date, width: "half", label: "Alternate Date (2nd Choice)" }, { type: :select, width: "half", label: "Alternate Time (2nd Choice)" }],
            [{ type: :select, width: "half", label: "Preferred Dealership Location" }, { type: :select, width: "half", label: "Desired Test Drive Duration" }],
            [{ type: :radio, width: "full", label: "Are you planning to trade in a vehicle?" }],
            [{ type: :input, width: "third", label: "Trade-In Year" }, { type: :input, width: "third", label: "Trade-In Make" }, { type: :input, width: "third", label: "Trade-In Model" }],
            [{ type: :number, width: "half", label: "Estimated Trade-In Mileage" }, { type: :select, width: "half", label: "Trade-In Condition" }],
            [{ type: :select, width: "half", label: "Expected Purchase Timeline" }, { type: :select, width: "half", label: "Financing Preference (Cash, Finance, Lease)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Additional Info" }],
            [{ type: :textarea, width: "full", label: "Questions or Comments for Sales Consultant" }],
            [{ type: :checkbox, width: "full", label: "I agree to provide a valid driver's license and proof of insurance at the time of the test drive" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "date" => "half",
              "number" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "time" => "half",
            },
            sections: [
              { label: "Contact Info", match_types: %w[text email tel] },
              { label: "Vehicle & Schedule", match_types: %w[select date number radio checkbox time] },
              { label: "Additional Info", match_types: %w[textarea] }
            ],
            inject_elements: [
              { after_section: 0, type: "divider" }, { after_section: 1, type: "divider" }
            ]
          }
        }.freeze
      end
    end
  end
end
