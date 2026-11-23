require "rails_helper"

RSpec.describe Admin::Settings::MemberSourceRowComponent, type: :component do
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

  context "editable source" do
    before { render_inline(described_class.new(presenter: presenter, editable: true, customer: customer)) }

    it "renders surface label, enabled checkbox in auto-submit form, and Edit link" do
      aggregate_failures do
        expect(page).to have_text("Payments")
        expect(page).to have_css("form[data-controller~='auto-submit']")
        expect(page).to have_css("input[type='checkbox'][name='member_settings[rows][0][enabled]']")
        expect(page).to have_link("Display settings",
          href: "/#{customer.id}/admin/settings/member/sources/modules/surfaces/payments")
      end
    end

    it "keeps the immediate-save payload limited to identity and visibility" do
      expect(page).to have_css("input[data-action='change->auto-submit#submit']")
      expect(page).not_to have_css("input[name*='visible_column_keys']", visible: :all)
      expect(page).not_to have_css("input[name*='visible_section_keys']", visible: :all)
      expect(page).not_to have_css("input[name*='visible_detail_row_keys']", visible: :all)
    end
  end

  context "non-editable source" do
    it "renders read-only without a form wrapper" do
      render_inline(described_class.new(presenter: presenter, editable: false, customer: customer))
      aggregate_failures do
        expect(page).not_to have_css("form")
        expect(page).to have_text("Payments")
      end
    end
  end
end
