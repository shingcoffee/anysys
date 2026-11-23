# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Contracts::ConversationTitle do
  def form_for(title)
    described_class.new(described_class::Input.new).tap { |form| form.validate(title: title) }
  end

  def limit
    AiAssistant::Conversation::TITLE_LIMIT
  end

  it "accepts a name the sidebar can show" do
    form = form_for("Cohort import")

    expect(form.errors).to be_empty
    expect(form.normalized_title).to eq("Cohort import")
  end

  it "accepts a name exactly at the column limit" do
    expect(form_for("x" * limit).errors).to be_empty
  end

  it "reports the contract as invalid rather than raising" do
    expect(described_class.new(described_class::Input.new).validate(title: " ")).to be false
    expect(described_class.new(described_class::Input.new).validate(title: "Cohort import")).to be true
  end

  describe "a name with nothing in it" do
    it "rejects a blank title" do
      expect(form_for("").errors[:title]).to include(I18n.t("ai_assistant.errors.title_blank"))
    end

    it "rejects a nil title" do
      expect(form_for(nil).errors[:title]).to include(I18n.t("ai_assistant.errors.title_blank"))
    end

    it "rejects a whitespace-only title" do
      expect(form_for("   ").errors[:title]).to include(I18n.t("ai_assistant.errors.title_blank"))
    end

    it "rejects a title made only of newlines and tabs" do
      expect(form_for("\n\t \r\n").errors[:title]).to include(I18n.t("ai_assistant.errors.title_blank"))
    end
  end

  describe "a name that is too long" do
    it "rejects a title over the column limit" do
      expect(form_for("x" * (limit + 1)).errors[:title])
        .to include(I18n.t("ai_assistant.errors.title_too_long"))
    end

    # This is why the contract exists: the model caps the column too, so an
    # over-long title would otherwise surface as a RecordInvalid.
    it "does not also report it as blank" do
      expect(form_for("x" * (limit + 1)).errors[:title])
        .not_to include(I18n.t("ai_assistant.errors.title_blank"))
    end

    it "measures the collapsed form, so padding alone cannot push it over" do
      expect(form_for("#{"x" * limit}\n   ").errors).to be_empty
    end
  end

  describe "#normalized_title" do
    it "collapses runs of whitespace and newlines" do
      expect(form_for("  My   chat\n\nname  ").normalized_title).to eq("My chat name")
    end

    it "collapses tabs and carriage returns" do
      expect(form_for("A\tB\r\nC").normalized_title).to eq("A B C")
    end

    it "is the same rule the model applies to a borrowed title" do
      raw = " Import   the\n cohort  list "

      expect(form_for(raw).normalized_title)
        .to eq(AiAssistant::Conversation.collapse_whitespace(raw))
    end

    it "is an empty string for a blank title" do
      expect(form_for(nil).normalized_title).to eq("")
      expect(form_for("  \n ").normalized_title).to eq("")
    end
  end
end
