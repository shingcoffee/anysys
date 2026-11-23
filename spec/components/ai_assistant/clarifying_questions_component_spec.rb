# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::ClarifyingQuestionsComponent, type: :component do
  def question(overrides = {})
    {
      "id" => "q1",
      "prompt" => "Which stages does your pipeline use?",
      "type" => "multiple",
      "options" => %w[Qualification Proposal Negotiation],
      "default" => %w[Qualification Proposal]
    }.merge(overrides)
  end

  def single_question
    question(
      "id" => "q2",
      "prompt" => "Should Opportunity link to your Account records?",
      "type" => "single",
      "options" => [ "Link to Account", "Store the company name as text" ],
      "default" => "Link to Account"
    )
  end

  def text_question
    question(
      "id" => "q3",
      "prompt" => "Opening hours",
      "type" => "text",
      "options" => [],
      "default" => "Mon–Sat 8:00–18:00"
    )
  end

  def render_card(questions, state: :open)
    render_inline(described_class.new(questions: questions, state: state))
  end

  def t(key)
    I18n.t("ai_assistant.assistant.questions.#{key}")
  end

  describe "whether there is anything to show" do
    it "renders nothing without questions" do
      [ nil, [], "nope" ].each do |value|
        render_card(value)

        expect(page).not_to have_css("[data-questions]")
      end
    end

    it "drops rows that are not usable hashes" do
      render_card(
        [
          "nope",
          nil,
          { "type" => "single", "options" => [ "A", "B" ] },
          { "prompt" => "  ", "type" => "text", "options" => [] },
          { "prompt" => "Hours", "type" => "essay", "options" => [] },
          { "prompt" => "Hours", "type" => "text", "options" => "nope" }
        ]
      )

      expect(page).not_to have_css("[data-questions]")
    end

    it "keeps a question whose options list mixes in non-strings" do
      render_card([ question("options" => [ "Qualification", 7, "", nil, "Proposal" ]) ])

      expect(page).to have_css("[data-questions='open']")
      expect(page).to have_text("Qualification")
      expect(page).to have_text("Proposal")
      expect(page).not_to have_text("7")
    end
  end

  describe "open markup" do
    it "wires the Stimulus card and keeps a hidden closed note for an in-place close" do
      render_card([ question, single_question, text_question ])

      card = page.find("[data-controller='ai-assistant-questions']")
      expect(card["data-questions"]).to eq("open")
      expect(card["data-action"]).to eq("ai-assistant-questions:answer->ai-assistant#answerQuestions")
      expect(card["data-ai-assistant-questions-no-preference-value"]).to eq(t("no_preference"))
      expect(card["data-ai-assistant-questions-list-separator-value"]).to eq(
        I18n.t("ai_assistant.assistant.plan.list_separator")
      )
      expect(card["data-ai-assistant-questions-skip-reply-value"]).to eq(t("skip_reply"))
      expect(card["aria-label"]).to eq(t("section"))
      expect(page).to have_text(t("title"))
      expect(page).to have_css("[data-questions-subtitle]", text: t("subtitle"))
      expect(page).to have_css("[data-questions-answered].hidden", text: t("answered"), visible: :all)
      expect(page).to have_css("[data-questions-footer]")
      expect(page).to have_css("[data-questions-send-label]", text: t("send"))
      expect(page).to have_css("[data-action='click->ai-assistant-questions#send']")
      expect(page).to have_css("[data-action='click->ai-assistant-questions#skip']", text: t("skip"))
    end

    it "renders each question type with defaults pre-selected" do
      render_card([ question, single_question, text_question ])

      expect(page).to have_css("fieldset[data-question-type='multiple'][data-question-prompt='#{question["prompt"]}']")
      expect(page).to have_css("fieldset[data-question-type='single'][data-question-prompt='#{single_question["prompt"]}']")
      expect(page).to have_css("fieldset[data-question-type='text'][data-question-prompt='#{text_question["prompt"]}']")
      expect(page).to have_css("legend", text: question["prompt"])
      expect(page).to have_css("input[type='checkbox'][value='Qualification'][checked]")
      expect(page).to have_css("input[type='checkbox'][value='Proposal'][checked]")
      expect(page).to have_css("input[type='checkbox'][value='Negotiation']:not([checked])")
      expect(page).to have_css("input[type='radio'][value='Link to Account'][checked]")
      expect(page).to have_css("input[type='radio'][value='Store the company name as text']:not([checked])")
      expect(page).to have_field(type: "text", with: "Mon–Sat 8:00–18:00")
      expect(page).to have_field(type: "text", placeholder: t("text_placeholder"))
      expect(page).to have_text(t("other"))
    end

    it "shares a radio name inside one single question and arrays checkboxes" do
      render_card([ single_question, question ])

      radios = page.all("fieldset[data-question-type='single'] input[type='radio']")
      expect(radios.map { |input| input[:name] }.uniq.size).to eq(1)
      checks = page.all("fieldset[data-question-type='multiple'] input[type='checkbox']")
      expect(checks.map { |input| input[:name] }.uniq).to all(end_with("[]"))
    end

    it "hides the number badge when there is only one question" do
      render_card([ text_question ])

      expect(page).to have_text("Opening hours")
      expect(page).not_to have_css("legend [aria-hidden='true']")
    end

    it "numbers questions from their id when more than one is present" do
      render_card([ question, single_question ])

      badges = page.all("legend [aria-hidden='true']").map(&:text)
      expect(badges).to eq(%w[1 2])
    end

    it "treats a bare-string multiple default as one selected option" do
      render_card([ question("default" => "Negotiation") ])

      expect(page).to have_css("input[type='checkbox'][value='Negotiation'][checked]")
      expect(page).to have_css("input[type='checkbox'][value='Qualification']:not([checked])")
    end

    it "treats an unrecognised state as still open" do
      render_card([ question ], state: :held)

      expect(page).to have_css("[data-questions='open']")
      expect(page).to have_css("[data-questions-footer]")
    end

    it "labels a text input from its legend" do
      render_card([ text_question ])

      legend = page.find("legend span.text-xs")
      input = page.find("[data-question-text]")
      expect(input["aria-labelledby"]).to eq(legend[:id])
    end
  end

  describe "closed markup" do
    it "shows the answered note without inputs, footer, or selected chips" do
      render_card([ question, single_question, text_question ], state: :closed)

      expect(page).to have_css("[data-questions='closed']")
      expect(page).to have_css("[data-questions-answered]", text: t("answered"))
      expect(page).not_to have_css("[data-questions-footer]")
      expect(page).not_to have_css("input")
      expect(page).not_to have_css("fieldset")
      expect(page).not_to have_text(t("subtitle"))
      expect(page).not_to have_text(t("send"))
      expect(page).to have_css("span", text: "Qualification")
      expect(page).to have_text("Opening hours")
      expect(page).not_to have_text("Mon–Sat 8:00–18:00")
    end
  end

  it "renders the title in zh-CN" do
    I18n.with_locale(:"zh-CN") do
      render_card([ question ])

      expect(page).to have_text(I18n.t("ai_assistant.assistant.questions.title", locale: :"zh-CN"))
    end
  end
end
