# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::Settings::Operation::Update do
  let_it_be(:customer) { create(:customer) }

  before do
    Member::Surfaces::SourceRegistry.reset!
    [Member::Sources::Builtin, Member::Sources::Modules, Member::Sources::Entities].each(&:register!)

    enable_module!("payment", customer, name: "Payments")
  end

  after { Member::Surfaces::SourceRegistry.reset! }

  # Calls the operation with `rows` wrapped in ActionController::Parameters (the
  # controller-realistic path). Cases that specifically exercise a plain Hash or
  # nested-hash `params` build them inline instead.
  def call_update(rows)
    described_class.call(
      customer: customer,
      params: ActionController::Parameters.new(rows: rows)
    )
  end

  # A single editable "payments" surface row; override any field via keywords.
  def payments_row(**overrides)
    { surface_key: "payments", enabled: "1" }.merge(overrides)
  end

  it "creates a SurfaceSetting row when none exists for the (customer, surface)" do
    expect {
      call_update([payments_row(label: "Donations")])
    }.to change(Member::SurfaceSetting, :count).by(1)
  end

  it "writes label / icon / subtitle / per_page / position into the row" do
    result = call_update([payments_row(
      position: "50",
      label: "Donations", icon: "heart", subtitle: "Past donations",
      empty_headline: "No donations yet",
      empty_body:     "Once you donate it'll show up here.",
      per_page: "5",
      visible_column_keys: %w[date amount],
      visible_detail_row_keys: %w[amount],
      visible_section_keys: %w[primary]
    )])
    expect(result.success?).to be(true)

    row = Member::SurfaceSetting.find_by!(customer: customer, surface_key: "payments")
    expect(row.enabled).to be(true)
    expect(row.position).to eq(50)
    expect(row.label_or("X")).to eq("Donations")
    expect(row.icon_or(:credit_card)).to eq(:heart)
    expect(row.subtitle_or("X")).to eq("Past donations")
    expect(row.empty_headline_or("X")).to eq("No donations yet")
    expect(row.per_page_or(20)).to eq(5)
    expect(row.visible_column_keys).to eq([:date, :amount])
    expect(row.visible_detail_row_keys).to eq([:amount])
    expect(row.visible_section_keys).to eq([:primary])
  end

  context "with saved customized preferences" do
    let!(:setting) do
      Member::SurfaceSetting.new(
        customer: customer, surface_key: "payments", source_key: "modules",
        enabled: true, position: 50
      ).tap do |row|
        row.write_overlay(
          label: "Donations", icon: :heart, subtitle: "Past donations",
          empty_headline: "No donations yet", empty_body: "Your donations appear here.",
          per_page: 5,
          visible_column_keys: %w[date amount],
          visible_detail_row_keys: %w[amount],
          visible_section_keys: %w[primary]
        )
        row.save!
      end
    end

    it "preserves all omitted preferences when toggling surface visibility" do
      saved_config = setting.config_json.deep_dup

      { "0" => false, "1" => true }.each do |enabled, expected|
        result = call_update([payments_row(enabled: enabled)])

        expect(result.success?).to be(true)
        setting.reload
        expect(setting.enabled).to be(expected)
        expect(setting.position).to eq(50)
        expect(setting.config_json).to eq(saved_config)
      end
    end

    %i[visible_column_keys visible_detail_row_keys visible_section_keys].each do |key|
      it "accepts a blank sentinel plus 50 real #{key} without storing the sentinel" do
        saved_config = setting.config_json.deep_dup
        keys = Array.new(50) { |i| "k#{i}" }

        result = call_update("0" => payments_row(**{ key => ["", *keys] }))

        expect(result.success?).to be(true)
        expect(setting.reload.config_json).to eq(saved_config.merge(key.to_s => keys))
      end

      it "rejects 51 real #{key} with or without a sentinel without changing saved preferences" do
        saved_config = setting.config_json.deep_dup
        keys = Array.new(51) { |i| "k#{i}" }

        [keys, ["", *keys]].each do |submitted_keys|
          result = call_update("0" => payments_row(**{ key => submitted_keys }))

          expect(result.success?).to be(false)
          expect(result.errors.full_messages.join).to include("must contain at most 50 entries")
          expect(setting.reload.config_json).to eq(saved_config)
        end
      end

      it "hides optional choices for sentinel-only #{key} while preserving omitted preferences" do
        saved_config = setting.config_json.deep_dup

        result = call_update("0" => payments_row(**{ key => [""] }))

        expect(result.success?).to be(true)
        setting.reload
        expect(setting.config_json).to eq(saved_config.merge(key.to_s => []))
        expect(setting.public_send(key)).to eq([])
      end

      it "hides optional choices for explicitly empty #{key} while preserving omitted preferences" do
        saved_config = setting.config_json.deep_dup

        result = call_update([payments_row(**{ key => [] })])

        expect(result.success?).to be(true)
        setting.reload
        expect(setting.config_json).to eq(saved_config.merge(key.to_s => []))
        expect(setting.public_send(key)).to eq([])
      end

      it "accepts explicit nil #{key} as inheritance without changing omitted preferences" do
        saved_config = setting.config_json.deep_dup

        result = call_update([payments_row(**{ key => nil })])

        expect(result.success?).to be(true)
        expect(setting.reload.public_send(key)).to be_nil
        expect(setting.config_json).to eq(saved_config.except(key.to_s))
      end
    end

    it "normalizes explicitly supplied scalar visibility keys into stored string lists" do
      result = call_update([payments_row(
        visible_column_keys: "date",
        visible_detail_row_keys: "status",
        visible_section_keys: "secondary"
      )])

      expect(result.success?).to be(true)
      expect(setting.reload.config_json).to include(
        "visible_column_keys" => ["date"],
        "visible_detail_row_keys" => ["status"],
        "visible_section_keys" => ["secondary"]
      )
    end

    it "clears explicit blank copy overrides without treating omitted copy as blank" do
      result = call_update([payments_row(label: "", empty_headline: "", empty_body: "")])

      expect(result.success?).to be(true)
      expect(setting.reload.label_or("Default label")).to eq("Default label")
      expect(setting.empty_headline_or("Default headline")).to eq("Default headline")
      expect(setting.empty_body_or("Default body")).to eq("Default body")
      expect(setting.subtitle_or("Default subtitle")).to eq("Past donations")
      expect(setting.per_page_or(20)).to eq(5)
    end
  end

  describe "atomic batches" do
    it "does not write a valid earlier row when a later surface is unknown" do
      result = nil
      expect {
        result = call_update([payments_row(label: "Must not save"), { surface_key: "phantom", enabled: "0" }])
      }.not_to change(Member::SurfaceSetting, :count)
      expect(result.success?).to be(false)
    end

    it "preserves an existing overlay when a later surface is unknown" do
      call_update([payments_row(label: "Original")])
      setting = Member::SurfaceSetting.find_by!(customer: customer, surface_key: "payments")
      original = setting.config_json.deep_dup

      result = call_update([payments_row(label: "Must not save"), { surface_key: "phantom" }])

      expect(result.success?).to be(false)
      expect(setting.reload.config_json).to eq(original)
    end

    it "rolls the first save back if a later model save fails" do
      call_update([payments_row(label: "Original")])
      setting = Member::SurfaceSetting.find_by!(customer: customer, surface_key: "payments")
      original = setting.config_json.deep_dup
      allow_any_instance_of(Member::SurfaceSetting).to receive(:save!).and_wrap_original do |method, *args|
        if method.receiver.label_or("") == "Rejected"
          method.receiver.errors.add(:base, :invalid)
          raise ActiveRecord::RecordInvalid.new(method.receiver)
        end
        method.call(*args)
      end

      result = call_update([payments_row(label: "First write"), payments_row(label: "Rejected")])

      expect(result.success?).to be(false)
      expect(setting.reload.config_json).to eq(original)
    end

    it "merges into fresh persisted settings instead of clobbering an intervening customization" do
      call_update([payments_row(label: "Original", per_page: 5)])
      setting = Member::SurfaceSetting.find_by!(customer: customer, surface_key: "payments")
      setting.write_overlay(subtitle: "Intervening edit")
      setting.save!

      result = call_update([payments_row(enabled: "0")])

      expect(result.success?).to be(true)
      expect(setting.reload.subtitle_or("Default")).to eq("Intervening edit")
      expect(setting.label_or("Default")).to eq("Original")
      expect(setting.per_page_or(20)).to eq(5)
    end
  end

  it "rejects an unknown surface_key" do
    result = call_update([{ surface_key: "xyzzy", enabled: "1" }])
    expect(result.success?).to be(false)
    expect(result.errors.full_messages.join).to include("is not a valid surface for this customer")
  end

  it "rejects per_page over 200" do
    result = call_update([payments_row(per_page: "9999")])
    expect(result.success?).to be(false)
  end

  it "is idempotent — calling twice does not create duplicate rows" do
    call_update([payments_row])
    expect {
      call_update([payments_row(enabled: "0", label: "Different")])
    }.not_to change(Member::SurfaceSetting, :count)

    row = Member::SurfaceSetting.find_by!(customer: customer, surface_key: "payments")
    expect(row.enabled).to be(false)
    expect(row.label_or("X")).to eq("Different")
  end

  it "writes source_key from the resolved EffectiveSurface" do
    result = call_update([payments_row])
    expect(result.success?).to be(true)
    row = Member::SurfaceSetting.find_by!(customer: customer, surface_key: "payments")
    expect(row.source_key).to eq("modules")
  end

  it "silently drops rows whose source is not editable" do
    expect {
      call_update([{ surface_key: "builtin_home", enabled: "0", label: "ATTACK" }])
    }.not_to change(Member::SurfaceSetting, :count)
  end

  it "rejects rows whose surface_key does not resolve for this customer" do
    result = call_update([{ surface_key: "phantom", enabled: "1" }])
    expect(result.success?).to be(false)
  end

  it "rejects oversized visible_column_keys arrays" do
    over_cap = Array.new(51) { |i| "k#{i}" }
    result = call_update([payments_row(visible_column_keys: over_cap)])
    expect(result.success?).to be(false)
    expect(result.errors.full_messages.join).to include("must contain at most 50 entries")
  end

  it "accepts a plain Hash (not ActionController::Parameters) for params" do
    result = described_class.call(
      customer: customer,
      params: { rows: [{ surface_key: "payments", enabled: "1", label: "Via Hash" }] }
    )
    expect(result.success?).to be(true)
    row = Member::SurfaceSetting.find_by!(customer: customer, surface_key: "payments")
    expect(row.label_or("X")).to eq("Via Hash")
  end

  it "accepts params whose rows are keyed as a Hash (Rails nested params style)" do
    result = described_class.call(
      customer: customer,
      params: { rows: { "0" => { surface_key: "payments", enabled: "1", label: "Hash-keyed" } } }
    )
    expect(result.success?).to be(true)
    row = Member::SurfaceSetting.find_by!(customer: customer, surface_key: "payments")
    expect(row.label_or("X")).to eq("Hash-keyed")
  end

  it "treats missing rows key as empty and succeeds" do
    result = described_class.call(customer: customer, params: {})
    expect(result.success?).to be(true)
  end

  it "ignores non-hash rows instead of 500ing" do
    result = described_class.call(
      customer: customer,
      params: { rows: ["x", { surface_key: "payments", enabled: "1", label: "Kept" }] }
    )

    expect(result.success?).to be(true)
    row = Member::SurfaceSetting.find_by!(customer: customer, surface_key: "payments")
    expect(row.label_or("X")).to eq("Kept")
  end

  it "keeps enabled nil when only overlay fields are submitted" do
    result = call_update([{ surface_key: "payments", label: "Donations" }])
    expect(result.success?).to be(true)

    row = Member::SurfaceSetting.find_by!(customer: customer, surface_key: "payments")
    expect(row.enabled).to be_nil
    expect(row.label_or("X")).to eq("Donations")
  end

  describe "row action overlay" do
    it "saves and reloads the three overlay keys" do
      result = call_update([payments_row(
        row_action_key: "enroll", row_action_field: "course", row_action_label: "Enroll"
      )])
      expect(result.success?).to be(true)

      row = Member::SurfaceSetting.find_by!(customer: customer, surface_key: "payments")
      expect(row.row_action_or("Open")).to eq(
        action_key: "enroll", field: "course", label: "Enroll"
      )
    end

    it "uses the default label when none is submitted" do
      result = call_update([payments_row(row_action_key: "enroll", row_action_field: "course")])
      expect(result.success?).to be(true)

      row = Member::SurfaceSetting.find_by!(customer: customer, surface_key: "payments")
      expect(row.row_action_or("Open")).to eq(
        action_key: "enroll", field: "course", label: "Open"
      )
    end

    it "rejects a key without a field" do
      result = call_update([payments_row(row_action_key: "enroll")])
      expect(result.success?).to be(false)
      expect(result.errors.full_messages.join).to include(
        I18n.t("admin_settings.errors.validations.row_action_invalid")
      )
    end

    it "rejects a field without a key" do
      result = call_update([payments_row(row_action_field: "course")])
      expect(result.success?).to be(false)
      expect(result.errors.full_messages.join).to include(
        I18n.t("admin_settings.errors.validations.row_action_invalid")
      )
    end

    it "clears the overlay when both key and field are blank" do
      call_update([payments_row(row_action_key: "enroll", row_action_field: "course", row_action_label: "Enroll")])

      result = call_update([payments_row(row_action_key: "", row_action_field: "", row_action_label: "")])
      expect(result.success?).to be(true)

      row = Member::SurfaceSetting.find_by!(customer: customer, surface_key: "payments")
      expect(row.row_action_or("Open")).to be_nil
    end

    it "rejects an action key that is not an action-key slug" do
      result = call_update([payments_row(row_action_key: "Enroll!", row_action_field: "course")])
      expect(result.success?).to be(false)
    end

    it "rejects a field that is not a form-param slug" do
      result = call_update([payments_row(row_action_key: "enroll", row_action_field: "course-id")])
      expect(result.success?).to be(false)
    end

    it "rejects a label longer than 60 characters" do
      result = call_update([payments_row(
        row_action_key: "enroll", row_action_field: "course", row_action_label: "x" * 61
      )])
      expect(result.success?).to be(false)
    end
  end
end
