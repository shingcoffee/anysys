# frozen_string_literal: true

require "rails_helper"
require "yaml"

RSpec.describe "element i18n keys" do
  locales = %w[en zh-CN]
  root = Rails.root

  define_method(:present?) do |key, locale|
    I18n.exists?(key, locale, fallback: false) &&
      I18n.t(key, locale: locale, fallback: false, raise: true).is_a?(String)
  end

  define_method(:flatten_keys) do |value, prefix = nil|
    case value
    when Hash
      value.flat_map { |key, item| flatten_keys(item, [prefix, key].compact.join(".")) }
    else
      [prefix]
    end
  end

  define_method(:load_tree) do |locale|
    Dir[root.join("config/locales/flowchart_elements*.#{locale}.yml")].sort.each_with_object({}) do |path, acc|
      payload = YAML.safe_load_file(path).fetch(locale).fetch("flowchart_elements")
      acc.deep_merge!(payload)
    end
  end

  define_method(:variables) do |key, locale|
    I18n.t(key, locale: locale, fallback: false, raise: true).scan(/%\{(\w+)\}/).flatten.uniq.sort
  end

  it "keeps identical key sets across flowchart_elements*.yml locales" do
    english = flatten_keys(load_tree("en")).sort
    chinese = flatten_keys(load_tree("zh-CN")).sort
    expect(chinese).to eq(english)
  end

  it "has a label (and option labels) for every exported element field in both locales" do
    missing = []
    locales.each do |locale|
      catalog = CodeGenerators::ElementCatalog.export(locale: locale)
      catalog.fetch("types").each_value do |type|
        type.fetch("fields").each do |field|
          unless field["label"].is_a?(String) && field["label"].present?
            missing << "#{locale} #{type["type"]}.#{field["name"]} label"
          end
          Array(field["options"]).each do |option|
            next if option["value"].to_s.empty?

            unless option["label"].is_a?(String) && option["label"].present? && option["label"] != option["value"].to_s
              missing << "#{locale} #{type["type"]}.#{field["name"]} option #{option["value"]}"
            end
          end
        end
      end
      catalog.fetch("connection").fetch("fields").each do |field|
        missing << "#{locale} connection.#{field["name"]} label" unless field["label"].present?
      end
    end
    expect(missing).to eq([])
  end

  it "resolves type labels, chrome, and shared error keys without fallbacks" do
    missing = []
    locales.each do |locale|
      %w[start end process decision loop subflow].each do |type|
        %w[label defaultLabel].each do |part|
          key = "flowchart_elements.#{type}.#{part}"
          missing << "#{locale} #{key}" unless present?(key, locale)
        end
      end
      %w[chrome.label.label shared.none shared.errors.required shared.errors.unknown_field].each do |suffix|
        key = "flowchart_elements.#{suffix}"
        missing << "#{locale} #{key}" unless present?(key, locale)
      end
    end
    expect(missing).to eq([])
  end

  it "keeps identical %{} variables in en and zh-CN for shared element errors" do
    mismatches = load_tree("en").dig("shared", "errors").keys.filter_map do |code|
      key = "flowchart_elements.shared.errors.#{code}"
      vars = locales.to_h { |locale| [locale, variables(key, locale)] }
      "#{key}: #{vars.inspect}" if vars.values.uniq.size > 1
    end
    expect(mismatches).to eq([])
  end
end
