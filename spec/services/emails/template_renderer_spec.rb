# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::TemplateRenderer do
  let(:customer) { create(:customer) }
  let!(:first_name_token) do
    Emails::TemplateToken.find_or_create_by!(
      customer_id: nil,
      source_type: Emails::TemplateToken::SOURCE_PLATFORM,
      source_key: "authentication_user.first_name"
    ) { |t| t.label = "First name" }
  end
  let!(:last_name_token) do
    Emails::TemplateToken.find_or_create_by!(
      customer_id: nil,
      source_type: Emails::TemplateToken::SOURCE_PLATFORM,
      source_key: "authentication_user.last_name"
    ) { |t| t.label = "Last name" }
  end
  let(:first_name_uuid) { first_name_token.uuid }
  let(:last_name_uuid) { last_name_token.uuid }

  describe ".render" do
    let(:template) do
      build(:email_template,
            customer: customer,
            subject: "Hello {{#{first_name_uuid}}}!",
            body_html: "<p>Welcome, {{#{first_name_uuid}}} {{#{last_name_uuid}}}.</p>",
            body_text: nil)
    end
    let(:vars) { Emails::VariableContext.for(user: create(:user, customer: customer, first_name: "John", last_name: "Doe")) }

    it "interpolates UUID variables in subject" do
      result = described_class.render(template: template, vars: vars)
      expect(result[:subject]).to eq("Hello John!")
    end

    it "interpolates editor label tokens in subject and body" do
      label = first_name_token.display_label
      template.subject = "Hello {{#{label}}}!"
      template.body_html = "<p>Hi {{#{label}}}</p>"
      result = described_class.render(template: template, vars: vars)
      expect(result[:subject]).to eq("Hello John!")
      expect(result[:body_html]).to eq("<p>Hi John</p>")
    end

    it "interpolates dynamic module model attribute tokens" do
      token = Emails::TemplateToken.find_or_create_by!(
        source_type: Emails::TemplateToken::SOURCE_PLATFORM,
        source_key: "authentication_user.email"
      ) { |t| t.label = "User.email" }

      template = create(:email_template, subject: "Hello {{#{token.uuid}}}", body_html: "<p>Email: {{#{token.uuid}}}</p>")
      user = create(:user, email: "user@example.com")
      vars = Emails::VariableContext.for(user: user)

      res = described_class.render(template: template, vars: vars)
      expect(res[:subject]).to eq("Hello user@example.com")
      expect(res[:body_html]).to include("user@example.com")
    end

    it "interpolates UUID variables in body_html" do
      result = described_class.render(template: template, vars: vars)
      expect(result[:body_html]).to eq("<p>Welcome, John Doe.</p>")
    end

    it "auto-generates body_text from body_html when blank" do
      result = described_class.render(template: template, vars: vars)
      expect(result[:body_text]).to eq("Welcome, John Doe.")
    end

    it "uses provided body_text if present" do
      template.body_text = "Plain: {{#{first_name_uuid}}}"
      result = described_class.render(template: template, vars: vars)
      expect(result[:body_text]).to eq("Plain: John")
    end

    it "preserves plain-text markup characters while resolving tokens" do
      template.subject = "R&D <Guest> {{#{first_name_uuid}}}"
      template.body_text = "1 < 2 & 3 > 0 {{#{first_name_uuid}}}"
      rendered = described_class.render(template: template, vars: vars)

      expect(rendered[:subject]).to eq("R&D <Guest> John")
      expect(rendered[:body_text]).to eq("1 < 2 & 3 > 0 John")
    end

    it "overrides a live-profile unsubscribe URL with the queued envelope for body rendering" do
      user = create(:user, customer: customer)
      message = build_stubbed(:email_message, :campaign, customer: customer, to: user.email, metadata: { "user_id" => user.id })
      unsubscribe = Emails::TemplateToken.platform.find_by!(source_key: "unsubscribe_url")
      template.body_html = %(<a href="{{#{unsubscribe.uuid}}}">Unsubscribe</a>)
      original = user.email
      user.update!(email: "changed@example.com")
      context = Emails::VariableContext.for(user: user)

      rendered = described_class.render(template: template, vars: context, message: message)
      url = Nokogiri::HTML.fragment(rendered[:body_html]).at_css("a")["href"]
      token = CGI.unescape(URI.parse(url).path.split("/").last)
      expect(Emails::SendActivities::SendActivityUnsubscribe.emailed_address(token)).to eq(original)
      expect(context[:unsubscribe_url]).not_to eq(url)
    end

    context "with missing variables" do
      let(:vars) { { "email" => "a@example.com" } }

      it "leaves missing placeholders empty" do
        result = described_class.render(template: template, vars: vars)
        expect(result[:subject]).to eq("Hello !")
        expect(result[:body_html]).to eq("<p>Welcome,  .</p>")
      end
    end

    context "with fallbacks" do
      it "uses fallback if variable is missing or blank" do
        template = build(:email_template, customer: customer,
                                          subject: "Hi {{#{first_name_uuid}|fallback:\"Friend\"}}")
        expect(described_class.render(template: template, vars: {})[:subject]).to eq("Hi Friend")
        expect(described_class.render(template: template, vars: { "authentication_user" => { "first_name" => "" } })[:subject]).to eq("Hi Friend")
        user = create(:user, customer: customer, first_name: "Alice")
        expect(described_class.render(template: template, vars: Emails::VariableContext.for(user: user))[:subject]).to eq("Hi Alice")
      end
    end

    context "when a variable value contains HTML (E-SEC-1 injection guard)" do
      let(:template) do
        build(:email_template,
              customer: customer,
              subject: "Hi {{#{first_name_uuid}}}",
              body_html: "<p>Welcome, {{#{first_name_uuid}}}.</p>",
              body_text: nil)
      end
      let(:vars) { { "authentication_user" => { "first_name" => '<a href="http://evil.example">click</a>' } } }

      it "HTML-escapes the interpolated value in body_html so it renders inert" do
        result = described_class.render(template: template, vars: vars)
        expect(result[:body_html]).to include("&lt;a href=")
        expect(result[:body_html]).not_to include('<a href="http://evil.example">')
      end
    end

    context "with custom entity_attribute variables" do
      let!(:custom) do
        create(:email_template_token, customer: customer, label: "Tier", attribute_slug: "name")
      end
      let(:template) do
        build(:email_template, customer: customer,
                               subject: "Tier {{#{custom.uuid}}}",
                               body_html: "<p>{{#{custom.uuid}}}</p>")
      end

      it "renders custom variables as blank until User↔EntityEntry linkage exists" do
        result = described_class.render(template: template, vars: vars)
        expect(result[:subject]).to eq("Tier ")
        expect(result[:body_html]).to eq("<p></p>")
      end
    end

    context "with chip markup in body_html" do
      let(:template) do
        build(:email_template, customer: customer,
                               subject: "Hi",
                               body_html: %(<p>Hi <span class="email-token-chip" data-email-token-uuid="#{first_name_uuid}" contenteditable="false">First name</span></p>))
      end

      it "serializes chips to tokens before interpolating" do
        result = described_class.render(template: template, vars: vars)
        expect(result[:body_html]).to eq("<p>Hi John</p>")
      end
    end

    context "with a rich_text template whose stored body_html is stale" do
      let(:table_html) do
        '<figure class="lexxy-content__table-wrapper"><table><tbody>' \
          '<tr><th class="lexxy-content__table-cell--header"><p>H1</p></th>' \
          "<td><p>Hello {{#{first_name_uuid}}}</p></td></tr></tbody></table></figure>"
      end
      let(:template) do
        t = build(:email_template, :rich_text, customer: customer, subject: "Hi {{#{first_name_uuid}}}")
        t.body = table_html
        t.save!
        t.update_columns(body_html: table_html)
        t
      end

      it "recompiles from ActionText so email-safe table styles are present" do
        result = described_class.render(template: template, vars: vars)
        expect(result[:body_html]).to include("border-collapse: collapse")
        expect(result[:body_html]).to include("Hello John")
      end
    end
  end

  describe ".inject_tracking" do
    let(:message_id) { 42 }

    it "appends a single open pixel" do
      html = described_class.inject_tracking("<p>Hi</p>", message_id)
      expect(html.scan(%r{/email/track/#{message_id}/open}).size).to eq(1)
    end

    it "does not append a second pixel when one is already present" do
      once = described_class.inject_tracking("<p>Hi</p>", message_id)
      twice = described_class.inject_tracking(once, message_id)
      expect(twice.scan(%r{/email/track/#{message_id}/open}).size).to eq(1)
    end

    it "does not wrap unsubscribe links in the click tracker" do
      html = described_class.inject_tracking(
        '<a href="https://example.test/unsubscribe/tok">unsub</a>',
        message_id
      )
      expect(html).to include('href="https://example.test/unsubscribe/tok"')
      expect(html).not_to include("/email/track/#{message_id}/click")
    end

    it "preserves the canonical host, HTTPS protocol and port for click/open URLs" do
      allow(ActionMailer::Base).to receive(:default_url_options)
        .and_return(host: "mail.example.test", protocol: "https", port: 8443)

      html = described_class.inject_tracking('<a href="https://destination.test/page">Link</a>', message_id)
      doc = Nokogiri::HTML.fragment(html)
      expect(doc.at_css("a")["href"]).to start_with("https://mail.example.test:8443/email/track/#{message_id}/click")
      expect(doc.at_css("img")["src"]).to start_with("https://mail.example.test:8443/email/track/#{message_id}/open")
    end
  end
end
