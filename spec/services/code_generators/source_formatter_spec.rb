# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::SourceFormatter do
  def reformat(source, max_width: 40) = described_class.call(source, max_width: max_width)

  it "leaves source that fits untouched" do
    source = "ctx[:total] = sum(ctx[:items])"
    expect(reformat(source)).to eq(source)
  end

  it "puts the arguments of an over-long call one per line, keyword pairs included" do
    expect(reformat("ctx[:total] = Pricing.calculate(ctx, lines: ctx[:items], tax_rate: 0.1)"))
      .to eq(<<~RUBY.chomp)
        ctx[:total] = Pricing.calculate(
          ctx,
          lines: ctx[:items],
          tax_rate: 0.1
        )
      RUBY
  end

  it "wraps nested literals that are still too long after the outer call" do
    source = 'Mailer.deliver(ctx, to: ["alpha@example.com", "beta@example.com", "gamma@example.com"])'
    expect(reformat(source)).to eq(<<~RUBY.chomp)
      Mailer.deliver(
        ctx,
        to: [
          "alpha@example.com",
          "beta@example.com",
          "gamma@example.com"
        ]
      )
    RUBY
  end

  it "keeps the indentation of the line it wraps and a trailing do block" do
    source = <<~RUBY.chomp
      def step(ctx, **)
        Batch.run(ctx, records: ctx[:records], size: 100, label: "sync") do |record|
          record.save!
        end
      end
    RUBY
    expect(reformat(source, max_width: 60)).to eq(<<~RUBY.chomp)
      def step(ctx, **)
        Batch.run(
          ctx,
          records: ctx[:records],
          size: 100,
          label: "sync"
        ) do |record|
          record.save!
        end
      end
    RUBY
  end

  it "wraps hash literals and keeps every token" do
    source = 'ctx[:payload] = {"customer" => ctx[:customer_id], "amount" => ctx[:amount]}'
    formatted = reformat(source)
    expect(formatted).to eq(<<~RUBY.chomp)
      ctx[:payload] = {
        "customer" => ctx[:customer_id],
        "amount" => ctx[:amount]
      }
    RUBY
    expect(formatted.gsub(/\s+/, "")).to eq(source.gsub(/\s+/, ""))
  end

  it "allows a method chain after the wrapped list" do
    expect(reformat("ctx[:rows] = Entries.query(ctx, conditions: ctx[:filter], per_page: 50).records"))
      .to eq(<<~RUBY.chomp)
        ctx[:rows] = Entries.query(
          ctx,
          conditions: ctx[:filter],
          per_page: 50
        ).records
      RUBY
  end

  it "never splits an operand in the middle of an expression or a modifier" do
    [
      'return Loop.leave(ctx, :loop, {}) || Done unless ctx.dig(:model, :status) == "active"',
      "return Loop.fail_limit(ctx, :loop, max: 10, exports: {}) if state[:count] >= 10",
      'ready = ctx.dig(:model, :status) == "active" && ctx.dig(:model, :role) != "guest"',
      'return Loop.leave(ctx, :loop, {}) unless (ConditionInput.compare(ctx.dig(:model, :age), ">", 18))',
      "label = ctx[:vip] ? Labels.build(ctx, tier: :gold, locale: ctx[:locale]) : Labels.default(ctx)",
      "value = !!Settings.lookup(ctx, scope: :customer, key: ctx[:setting_key], fallback: nil)"
    ].each do |source|
      expect(reformat(source)).to eq(source)
    end
  end

  it "does not break single-element lists, strings, heredocs or unparsable source" do
    long_string = %(log("#{'x' * 50}"))
    interpolated = %(puts "#{'y' * 40} \#{a}, \#{b}")
    heredoc = "render(<<~TEXT, ctx)\n  #{'z' * 50}\nTEXT"
    broken = "call(a, b, c, d, e, f, g, h, i, j, k, l, m"

    [long_string, interpolated, heredoc, broken].each do |source|
      expect(reformat(source)).to eq(source)
    end
  end

  it "keeps multibyte text intact" do
    source = 'notify(ctx, title: "订单已发货", body: "您的订单已经发货，请注意查收")'
    expect(reformat(source, max_width: 30)).to eq(<<~RUBY.chomp)
      notify(
        ctx,
        title: "订单已发货",
        body: "您的订单已经发货，请注意查收"
      )
    RUBY
  end
end
