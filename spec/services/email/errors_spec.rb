# frozen_string_literal: true

require "rails_helper"

RSpec.describe Email::Errors do
  describe "hierarchy" do
    it "Email::Errors::Error is a StandardError" do
      expect(Email::Errors::Error.ancestors).to include(StandardError)
    end

    %w[CredentialsMissing TemplateNotFound TemplateVarsInvalid DailyCapExceeded InvalidRecipient].each do |klass_name|
      it "Email::Errors::#{klass_name} inherits from Email::Errors::Error" do
        klass = described_class.const_get(klass_name)
        expect(klass.ancestors).to include(Email::Errors::Error)
      end
    end
  end
end
