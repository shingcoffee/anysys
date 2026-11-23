require "rails_helper"

RSpec.describe Admin::Settings::MemberSurfaceFormComponent, type: :component do
  let_it_be(:customer) { create(:customer) }
  let(:descriptor) { FeatureModules::Payment::MemberSurface.build }
  let(:effective) do
    Member::EffectiveSurface.new(
      descriptor: descriptor,
      settings:   Member::NullSurfaceSetting.new,
      source_key: :modules
    )
  end
  let(:presenter) { Admin::Settings::MemberRowPresenter.new(effective: effective) }

  let(:component) { described_class.new(presenter: presenter, customer: customer) }

  before { render_inline(component) }

  it "renders the surface label and correct form action" do
    aggregate_failures do
      expect(page).to have_field("Display name", with: "Payments")
      expect(page).to have_css("form[action$='/admin/settings/member/sources/modules/surfaces/payments']")
    end
  end

  it "renders enabled checkbox and label/icon/subtitle inputs" do
    aggregate_failures do
      expect(page).to have_css("input[type='checkbox'][name='member_settings[rows][0][enabled]']")
      expect(page).to have_css("input[name='member_settings[rows][0][label]']")
      expect(page).to have_css("select[name='member_settings[rows][0][icon]']", visible: :all)
      expect(page).to have_css("input[name='member_settings[rows][0][subtitle]']")
    end
  end

  it "renders empty-state copy fields" do
    aggregate_failures do
      expect(page).to have_css("input[name='member_settings[rows][0][empty_headline]']")
      expect(page).to have_css("textarea[name='member_settings[rows][0][empty_body]']")
    end
  end

  it "renders one column checkbox per descriptor column with hideable=false locked" do
    locked = page.find("input[type='checkbox'][name='member_settings[rows][0][visible_column_keys][]'][value='amount']")
    expect(locked[:disabled]).to eq("disabled")
  end

  it "submits explicit empty arrays and retains required values in the full form" do
    %w[visible_column_keys visible_section_keys visible_detail_row_keys].each do |field|
      expect(page).to have_css("input[type='hidden'][name='member_settings[rows][0][#{field}][]'][value='']", visible: :all)
    end
    expect(page).to have_css("input[type='hidden'][name='member_settings[rows][0][visible_column_keys][]'][value='amount']", visible: :all)
  end

  it "labels icon choices without displaying their identifiers" do
    expect(page).to have_css("option[value='credit_card']", text: "Payment card", visible: :all)
    expect(page).not_to have_text("Surface key")
    expect(page).not_to have_text("credit_card")
    expect(page).to have_link("Cancel", href: "/#{customer.id}/admin/settings/member/sources/modules")
  end

  it "retains an existing icon outside the named choices without exposing its identifier" do
    allow(presenter).to receive(:icon).and_return("legacy_icon")
    render_inline(component)
    expect(page).to have_css("option[value='legacy_icon'][selected]", text: "Current icon", visible: :all)
    expect(page).not_to have_text("legacy_icon")
  end

  it "renders a built-in page as read-only even on its direct display URL" do
    render_inline(described_class.new(presenter: presenter, customer: customer, editable: false))
    expect(page).to have_text("These core pages cannot be hidden or reordered.")
    expect(page).not_to have_css("form")
    expect(page).not_to have_button("Save")
  end

  it "renders surface_key as a hidden field" do
    expect(page).to have_css(
      "input[type='hidden'][name='member_settings[rows][0][surface_key]'][value='payments']",
      visible: :hidden
    )
  end

  it "labels the untitled primary section without titleizing the key" do
    expect(page).to have_text("Primary")
  end

  it "localizes the untitled primary section in zh-CN" do
    I18n.with_locale(:"zh-CN") { render_inline(component) }
    expect(page).to have_text("主要")
  end

  it "does not render the row action group for a non-entity surface" do
    expect(page).not_to have_text(I18n.t("settings_people.row_action"))
    expect(page).not_to have_css("select[name='member_settings[rows][0][row_action_key]']")
  end

  context "on an entity surface" do
    def entity_descriptor
      Member::Surface.new(
        key: :entity_1, label: "Courses", icon: :rectangle_stack,
        enabled_for: ->(_) { true },
        index: Member::Surface::Index.new(
          title: "Courses",
          scope: ->(_) { [] },
          columns: [{ key: :name, label: "Name", value: ->(r) { r.name }, hideable: false }]
        ),
        detail: Member::Surface::Detail.new(
          title: ->(r) { r.name },
          sections: [{ key: :primary, rows: [{ key: :name, label: "Name", value: ->(r) { r.name } }] }]
        )
      )
    end

    def entity_presenter(settings: Member::NullSurfaceSetting.new)
      effective = Member::EffectiveSurface.new(
        descriptor: entity_descriptor,
        settings: settings,
        source_key: :entities
      )
      Admin::Settings::MemberRowPresenter.new(effective: effective)
    end

    it "renders the row action group with overlay field names" do
      render_inline(described_class.new(presenter: entity_presenter, customer: customer))

      expect(page).to have_text(I18n.t("settings_people.row_action"))
      expect(page).to have_css("select[name='member_settings[rows][0][row_action_key]']")
      expect(page).to have_css("input[name='member_settings[rows][0][row_action_field]']")
      expect(page).to have_css("input[name='member_settings[rows][0][row_action_label]']")
      expect(page).to have_css("option[value='']", text: I18n.t("comp_admin.member_surface_form.row_action_none"), visible: :all)
      expect(page).to have_text(I18n.t("comp_admin.member_surface_form.row_action_empty"))
    end

    it "lists action keys that have a launched member page for this customer" do
      create(:page, :launched, :member_only, customer: customer, action_key: "enroll")
      create(:page, :shared, :launched, :member_only, action_key: "renew")
      create(:page, :launched, customer: customer, action_key: "admin_only")
      create(:page, :for_member, customer: customer, action_key: "draft")
      create(:page, :launched, :member_only, customer: create(:customer), action_key: "foreign")

      render_inline(described_class.new(presenter: entity_presenter, customer: customer))

      expect(page).to have_css("option[value='enroll']", text: "enroll", visible: :all)
      expect(page).to have_css("option[value='renew']", text: "renew", visible: :all)
      expect(page).not_to have_css("option[value='admin_only']")
      expect(page).not_to have_css("option[value='draft']")
      expect(page).not_to have_css("option[value='foreign']")
      expect(page).not_to have_text(I18n.t("comp_admin.member_surface_form.row_action_empty"))
    end

    it "prefills overlay values and uses the default label as the placeholder" do
      setting = Member::SurfaceSetting.new
      setting.write_overlay(row_action_key: "enroll", row_action_field: "course", row_action_label: "Enroll")
      create(:page, :launched, :member_only, customer: customer, action_key: "enroll")

      render_inline(described_class.new(presenter: entity_presenter(settings: setting), customer: customer))

      expect(page).to have_css("select[name='member_settings[rows][0][row_action_key]'] option[value='enroll'][selected]", visible: :all)
      expect(page).to have_field(I18n.t("comp_admin.member_surface_form.row_action_field"), with: "course")
      expect(page).to have_field(I18n.t("comp_admin.member_surface_form.row_action_label"), with: "Enroll")
      expect(page).to have_css(
        "input[name='member_settings[rows][0][row_action_label]'][placeholder='#{I18n.t("member.entity_surfaces.row_action_default")}']"
      )
    end

    it "marks invalid key and field inputs and shows the alert" do
      message = I18n.t("admin_settings.errors.validations.row_action_invalid")
      render_inline(described_class.new(
        presenter: entity_presenter,
        customer: customer,
        errors: { row_action_key: [message], row_action_field: [message] }
      ))

      expect(page).to have_text(message)
      expect(page).to have_css("select[name='member_settings[rows][0][row_action_key]'][aria-invalid='true']")
      expect(page).to have_css("input[name='member_settings[rows][0][row_action_field]'][aria-invalid='true']")
    end
  end
end
