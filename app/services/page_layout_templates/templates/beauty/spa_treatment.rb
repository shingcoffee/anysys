# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Beauty
      module SpaTreatment
        DEFINITION = {
          key: "spa_treatment",
          name: "Spa Treatment Booking",
          description: "Spa or wellness treatment reservation with preferences and health notes",
          category: "beauty",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Guest Info" }],
            [{ type: :input, width: "half", label: "First Name" }, { type: :input, width: "half", label: "Last Name" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :radio, width: "full", label: "Are you a new guest or returning member?" }],
            [{ type: :input, width: "half", label: "Membership / Loyalty Number (if applicable)" }, { type: :date, width: "half", label: "Date of Birth (for birthday specials)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Treatment Details" }],
            [{ type: :date, width: "half", label: "Preferred Date" }, { type: :select, width: "half", label: "Preferred Time Slot" }],
            [{ type: :date, width: "half", label: "Alternate Date" }, { type: :select, width: "half", label: "Alternate Time Slot" }],
            [{ type: :select, width: "half", label: "Spa Location / Branch" }, { type: :radio, width: "half", label: "Therapist Gender Preference (Any, Female, Male)" }],
            [{ type: :select, width: "half", label: "Primary Treatment Type" }, { type: :select, width: "half", label: "Treatment Duration (60 min, 90 min, 120 min)" }],
            [{ type: :checkbox, width: "full", label: "Treatments (Swedish Massage, Deep Tissue, Hot Stone, Aromatherapy, Sports, Prenatal, Couples, Reflexology, Classic Facial, Anti-Aging Facial, Body Scrub, Body Wrap, Hydrotherapy)" }],
            [{ type: :input, width: "half", label: "Preferred Therapist (if known)" }, { type: :select, width: "half", label: "Room Preference (Standard, Couples Suite, VIP)" }],
            [{ type: :radio, width: "full", label: "Massage Pressure Preference (Light, Medium, Firm, Very Firm)" }],
            [{ type: :select, width: "half", label: "Aromatherapy Scent Preference" }, { type: :select, width: "half", label: "Music Preference (Spa Music, Nature Sounds, Silence)" }],
            [{ type: :textarea, width: "full", label: "Focus / Problem Areas (e.g., Lower Back, Shoulders, Neck)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Health & Add-ons" }],
            [{ type: :textarea, width: "full", label: "Known Allergies (Essential Oils, Lotions, Fragrances, Nuts)" }],
            [{ type: :textarea, width: "full", label: "Current Health Conditions or Injuries (Back Pain, Arthritis, Surgery, Skin Conditions)" }],
            [{ type: :checkbox, width: "full", label: "Health Concerns (High/Low Blood Pressure, Heart Condition, Diabetes, Varicose Veins, Recent Surgery, Pregnant/Nursing, Open Wounds)" }],
            [{ type: :checkbox, width: "full", label: "Add-On Services (Aromatherapy Upgrade, CBD Oil, Hot Stone Add-On, Scalp Treatment, Foot Scrub, Paraffin Wax, Eye Treatment, Extra 30 min)" }],
            [{ type: :input, width: "half", label: "Gift Certificate / Promo Code (if any)" }, { type: :radio, width: "half", label: "Is this a special occasion? (Birthday, Anniversary, Gift)" }],
            [{ type: :textarea, width: "full", label: "Special Requests or Notes for Spa Staff" }],
            [{ type: :checkbox, width: "full", label: "I agree to the 24-hour cancellation policy and spa etiquette guidelines" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "date" => "half",
              "select" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "time" => "half",
            },
            sections: [
              { label: "Guest Info", match_types: %w[text email tel] },
              { label: "Treatment Details", match_types: %w[select date radio checkbox time] },
              { label: "Health & Add-ons", match_types: %w[textarea] }
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
