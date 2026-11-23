# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::CodeGenerators::HelperReferenceComponent, type: :component do
  subject(:rendered) { render_inline(described_class.new) }

  it "documents every BaseGenerator helper" do
    expect(rendered.css("dt code").map(&:text)).to eq(described_class::HELPERS.values)
    expect(rendered.css("dd").map(&:text)).to all(be_present)
  end

  it "lists every config schema role" do
    expect(rendered.css("section:nth-of-type(2) code").map(&:text)).to eq(CodeGenerators::ConfigSchema::ROLES.map(&:to_s))
  end

  it "renders in Chinese" do
    I18n.with_locale(:"zh-CN") do
      expect(render_inline(described_class.new).text).to include("辅助方法", "配置角色")
    end
  end
end
