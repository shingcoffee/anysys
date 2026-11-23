# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageLayoutTemplates do
  describe ".all" do
    it "returns 211 templates" do
      expect(described_class.all.length).to eq(211)
    end

    it "returns templates with required keys" do
      described_class.all.each do |template|
        expect(template).to have_key(:key)
        expect(template).to have_key(:name)
        expect(template).to have_key(:description)
        expect(template).to have_key(:category)
        expect(template).to have_key(:theme_preset)
        expect(template).to have_key(:layout)
        expect(template).to have_key(:preview_rows)
      end
    end

    it "returns templates with unique keys" do
      keys = described_class.all.map { |t| t[:key] }
      expect(keys.uniq.length).to eq(keys.length)
    end

    it "includes all expected template keys" do
      keys = described_class.keys
      expected = %w[
        blank default member_default public_default compact_two_column three_column_grid sectioned_professional wizard_multi_step
        simple_signup detailed_registration user_profile
        contact_simple contact_detailed support_ticket
        product_listing order_form invoice_form expense_report vendor_registration
        customer_feedback nps_survey quiz_assessment employee_satisfaction market_research
        event_registration appointment_booking conference_registration
        job_application employee_onboarding
        patient_intake health_assessment prescription_refill
        course_enrollment assignment_submission scholarship_application parent_permission
        data_entry_admin settings_preferences
        donation_form payment_request subscription_form
        lead_capture newsletter_signup contest_entry webinar_registration
        property_inquiry rental_application
        consent_waiver incident_report nda_agreement
        travel_request hotel_reservation restaurant_reservation
        volunteer_registration membership_application petition_form
        time_off_request performance_review expense_reimbursement training_registration
        product_return customer_review wholesale_order gift_card_purchase
        bug_report feature_request website_feedback testimonial_collection
        party_rsvp wedding_rsvp potluck_signup reunion_registration
        restaurant_feedback room_service_order guest_checkin catering_order
        gym_membership class_booking personal_training_intake
        portfolio_submission photography_booking design_brief
        it_support_request equipment_request access_permission_request
        insurance_quote insurance_claim
        permit_application public_complaint
        vehicle_service test_drive_request
        vet_appointment pet_adoption
        building_inspection project_estimate
        salon_appointment spa_treatment
        daycare_enrollment
        team_registration
        consultation_request
        shipping_request
        research_consent
        loan_application
        church_event
        ticket_booking
        dental_patient_intake
        home_repair
        therapy_intake
        crop_report livestock_record
        quality_inspection work_order
        inventory_count customer_loyalty
        accounting_client_onboarding
        candidate_screening reference_check
        room_booking maintenance_request
        purchase_order
        tutoring_session
        moving_quote
        cleaning_quote
        visitor_signin
        restaurant_order recipe_submission
        desk_booking
        prescription_transfer
        beta_signup cancellation_survey
        community_membership
        medication_review
        afterschool_program
        player_registration
        project_brief
        freight_quote
        lab_sample_submission
        credit_card_application
        prayer_request
        venue_rental
        cosmetic_consultation
        plumbing_service
        counseling_feedback
        food_truck_booking
        onboarding_checklist
        progress_report
        access_card_request
        janitorial_inspection
        storage_rental
        vendor_evaluation
        parking_permit
        tax_document_upload
        exit_interview
        wedding_vendor_inquiry wedding_guest_rsvp
        lawn_care_quote tree_service_request
        ac_repair_request electrical_estimate
        senior_care_assessment senior_activity_signup
        audit_checklist policy_acknowledgment
        warranty_registration warranty_claim
        solar_quote outage_report
        brand_collaboration sponsorship_application
        virtual_visit_intake symptom_checker
        interior_style_quiz room_design_assessment
        pest_inspection_request pest_treatment_followup
        roof_inspection roof_repair_quote
        music_lesson_signup music_recital_registration
        eye_exam_booking contact_lens_reorder
        architectural_review hoa_violation_report
        bulk_pickup_request recycling_schedule
        funeral_service_arrangement memorial_tribute
        tattoo_consultation tattoo_aftercare_checkin
        laundry_pickup_request dry_cleaning_dropoff
        notary_appointment_request notary_document_certification
        pt_intake pt_progress_evaluation
        print_order sign_quote
        boat_service_request marina_slip_rental
        flight_training_enrollment aircraft_charter_request
        temp_staffing_request staffing_worker_application
        catering_quote_request catering_menu_selection
        library_card_application archive_research_request
        rfp_submission vendor_bid_response
        inventory_audit stock_reorder_request
      ]
      expect(keys).to match_array(expected)
    end

    it "orders templates by category then by key within each category" do
      templates = described_class.all
      category_order = described_class::CATEGORY_ORDER

      templates.each_cons(2) do |a, b|
        a_idx = category_order.index(a[:category]) || 999
        b_idx = category_order.index(b[:category]) || 999
        if a_idx == b_idx
          expect(a[:key] <= b[:key]).to be(true),
            "Expected '#{a[:key]}' <= '#{b[:key]}' within '#{a[:category]}' category"
        else
          expect(a_idx <= b_idx).to be(true),
            "Expected category '#{a[:category]}' before '#{b[:category]}'"
        end
      end
    end
  end

  describe ".find" do
    it "returns correct template for valid key" do
      template = described_class.find("contact_detailed")
      expect(template[:name]).to eq("Detailed Contact")
      expect(template[:theme_preset]).to eq("modern")
    end

    it "returns nil for invalid key" do
      expect(described_class.find("nonexistent")).to be_nil
    end

    it "returns nil for blank key" do
      expect(described_class.find("")).to be_nil
      expect(described_class.find(nil)).to be_nil
    end

    it "returns blank template" do
      template = described_class.find("blank")
      expect(template[:name]).to eq("Blank Canvas")
      expect(template[:layout][:field_width_rules]).to be_empty
    end

    it "accepts symbol keys" do
      template = described_class.find(:blank)
      expect(template[:name]).to eq("Blank Canvas")
    end

    it "translates catalog names and category labels for the active locale" do
      I18n.with_locale(:"zh-CN") do
        expect(described_class.find("blank")[:name]).to eq("空白画布")
        expect(described_class.category_label("general")).to eq("通用")
        group = described_class.category_groups.find { |item| item[:key] == "popular" }
        expect(described_class.category_group_label(group)).to eq("常用")
      end
    end
  end

  describe ".categories" do
    it "returns a hash of categories" do
      cats = described_class.categories
      expect(cats).to be_a(Hash)
      expect(cats.keys).to include("all", "general", "registration", "contact", "business", "survey", "scheduling", "application", "healthcare", "education", "payment", "marketing", "realestate", "legal", "travel", "nonprofit", "hr", "ecommerce", "feedback", "social", "hospitality", "fitness", "creative", "it", "insurance", "government", "automotive", "pets", "construction", "beauty", "childcare", "sports", "consulting", "logistics", "research", "banking", "religious", "entertainment", "dental", "homeservices", "mentalhealth", "agriculture", "manufacturing", "retail", "accounting", "recruitment", "facilities", "procurement", "tutoring", "moving", "cleaning", "security", "food", "coworking", "saas", "hoa", "optometry", "music", "roofing", "pestcontrol", "interiordesign", "telehealth", "creator", "energy", "warranty", "compliance", "seniorcare", "hvac", "landscaping", "wedding", "pharmacy", "waste", "funeral", "tattoo", "laundry", "notary", "physicaltherapy", "printing", "marine", "aviation", "staffing", "catering", "library", "bidding", "inventory")
    end

    it "has label and icon for each category" do
      described_class.categories.each do |key, cat|
        expect(cat).to have_key(:label), "Category '#{key}' missing :label"
        expect(cat).to have_key(:icon), "Category '#{key}' missing :icon"
      end
    end
  end

  describe ".category_groups" do
    it "returns an array of group hashes" do
      groups = described_class.category_groups
      expect(groups).to be_an(Array)
      expect(groups.length).to be > 0
    end

    it "has key, label, icon, and categories for each group" do
      described_class.category_groups.each do |group|
        expect(group).to have_key(:key), "Group missing :key"
        expect(group).to have_key(:label), "Group missing :label"
        expect(group).to have_key(:icon), "Group missing :icon"
        expect(group).to have_key(:categories), "Group missing :categories"
        expect(group[:categories]).to be_an(Array)
      end
    end

    it "references only valid category keys" do
      valid_keys = described_class.categories.keys - ["all"]
      described_class.category_groups.each do |group|
        group[:categories].each do |cat_key|
          expect(valid_keys).to include(cat_key),
            "Group '#{group[:key]}' references invalid category '#{cat_key}'"
        end
      end
    end

    it "covers all non-'all' categories across groups" do
      grouped_keys = described_class.category_groups.flat_map { |g| g[:categories] }
      all_category_keys = described_class.categories.keys - ["all"]
      missing = all_category_keys - grouped_keys
      expect(missing).to be_empty,
        "Categories not assigned to any group: #{missing.join(', ')}"
    end
  end

  describe ".for_category" do
    it "returns all templates for 'all' category" do
      expect(described_class.for_category("all").length).to eq(211)
    end

    it "returns all templates for blank category" do
      expect(described_class.for_category("")).to eq(described_class.all)
    end

    it "returns only matching templates for a specific category" do
      business = described_class.for_category("business")
      expect(business).not_to be_empty
      business.each do |t|
        expect(t[:category]).to eq("business")
      end
    end
  end

  describe "theme_preset validity" do
    it "maps all templates to valid ThemeResolver presets" do
      valid_presets = ThemeResolver::THEME_PRESETS.keys

      described_class.all.each do |template|
        expect(valid_presets).to include(template[:theme_preset]),
          "Template '#{template[:key]}' has invalid theme_preset '#{template[:theme_preset]}'"
      end
    end
  end

  describe "layout structure" do
    it "has layout hash with required keys for each template" do
      described_class.all.each do |template|
        layout = template[:layout]
        expect(layout).to have_key(:default_width)
        expect(layout).to have_key(:field_width_rules)
        expect(layout).to have_key(:sections)
        expect(layout).to have_key(:inject_elements)
      end
    end

    it "only references valid HTML types in field_width_rules" do
      # Accept both HtmlTypeOptions and PageContentGenerator::HTML_TYPE_COMPONENTS
      valid_types = HtmlTypeOptions.all_html_types.map(&:last)
      valid_types += PageContentGenerator::HTML_TYPE_COMPONENTS.keys

      described_class.all.each do |template|
        template[:layout][:field_width_rules].each_key do |html_type|
          expect(valid_types).to include(html_type),
            "Template '#{template[:key]}' references invalid html_type '#{html_type}'"
        end
      end
    end

    it "only uses valid width values in field_width_rules" do
      valid_widths = %w[full half third two_thirds]

      described_class.all.each do |template|
        template[:layout][:field_width_rules].each_value do |width|
          expect(valid_widths).to include(width),
            "Template '#{template[:key]}' uses invalid width '#{width}'"
        end
      end
    end
  end

  describe "preview_rows structure" do
    it "has preview_rows as an array for each template" do
      described_class.all.each do |template|
        expect(template[:preview_rows]).to be_an(Array),
          "Template '#{template[:key]}' has non-array preview_rows"
      end
    end

    it "has valid element types in preview_rows" do
      valid_types = %i[section input textarea select checkbox radio date number rating file divider spacer button steps signature]

      described_class.all.each do |template|
        template[:preview_rows].each do |row|
          row.each do |el|
            expect(valid_types).to include(el[:type]),
              "Template '#{template[:key]}' has invalid preview element type '#{el[:type]}'"
          end
        end
      end
    end

    it "has valid width values in preview elements" do
      valid_widths = %w[full half third]

      described_class.all.each do |template|
        template[:preview_rows].each do |row|
          row.each do |el|
            next unless el[:width]
            expect(valid_widths).to include(el[:width]),
              "Template '#{template[:key]}' has invalid preview width '#{el[:width]}'"
          end
        end
      end
    end
  end

  describe ".keys" do
    it "returns array of all template keys" do
      expect(described_class.keys).to be_an(Array)
      expect(described_class.keys.first).to eq("blank")
    end
  end

  describe ".by_category" do
    it "groups templates by category" do
      grouped = described_class.by_category
      expect(grouped).to be_a(Hash)
      expect(grouped.keys).to include("general", "registration", "business")
    end
  end

  describe ".category_counts" do
    it "includes total count under 'all'" do
      expect(described_class.category_counts["all"]).to eq(211)
    end

    it "counts each category correctly" do
      counts = described_class.category_counts
      counts.each do |cat, count|
        next if cat == "all"
        expect(described_class.for_category(cat).length).to eq(count)
      end
    end
  end

  describe "file structure" do
    it "has a template file for each category" do
      template_dir = Rails.root.join("app/services/page_layout_templates/templates")
      categories_with_templates = described_class.all.map { |t| t[:category] }.uniq

      categories_with_templates.each do |cat|
        expect(template_dir.join(cat)).to be_directory,
          "Missing template directory for category '#{cat}'"
      end
    end

    it "has one file per template" do
      template_dir = Rails.root.join("app/services/page_layout_templates/templates")
      files = Dir[template_dir.join("**/*.rb")]

      expect(files.length).to eq(described_class.all.length)
    end
  end

  describe PageLayoutTemplates::Registry do
    describe ".reload!" do
      it "clears cached templates" do
        described_class.all
        described_class.reload!

        expect(described_class.all.length).to eq(211)
      end
    end
  end
end
