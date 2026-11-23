# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Finance
        class CalculatePricingGenerator < BaseGenerator
          DISCOUNT_TYPES = FlowchartRuntime::Pricing::DISCOUNT_TYPES
          TAX_MODES = FlowchartRuntime::Pricing::TAX_MODES
          ROUND_PER = FlowchartRuntime::Pricing::ROUND_PER
          ROUNDING_MODES = FlowchartRuntime::Money::ROUNDING.keys.freeze

          generator_metadata do
            description "Totals an order, invoice, or quote from line items. Order of operations is fixed: line gross (quantity times unit price), minus per-line discount, then order-level discount split across remaining line nets with largest remainder (never below zero), then tax, then shipping. Exclusive tax adds on payable; inclusive extracts tax from the entered price; none skips tax. Use request_payment to charge the total, or allocate_amount to split it. Reads sourceVariable. Writes the pricing hash (lines, subtotal, discount, tax, shipping, total, currency) to resultVar as decimal strings. Refuses calculate_pricing.invalid_line for a non-numeric or negative quantity or unit price."
            category :finance
            version "1.1.0"
            presentation icon: "M9 14l6-6m-5.5.5a2.5 2.5 0 11-5 0 2.5 2.5 0 015 0zm10.5-1a2.5 2.5 0 11-5 0 2.5 2.5 0 015 0z",
                         color: "emerald", single_use: false, privileged: false
          end

          config_schema do
            input :sourceVariable, required: true, example: "line_items",
                  description: "Ctx path of the line-item array, such as line_items. Each item is a hash or EntityEntry with quantity and unit-price keys. A single hash or record is treated as one line."
            literal :quantityField, default: "quantity",
                    description: "Key read from each line for quantity, such as quantity. Must be a non-negative number."
            literal :unitPriceField, default: "unit_price",
                    description: "Key read from each line for unit price, such as unit_price. Must be a non-negative number. Entered in the same units as tax, discount, and shipping."
            literal :lineDiscountField, default: "", group: :advanced,
                    description: "Optional key for a per-line discount amount, such as line_discount. Applied before the order-level discount. Leave blank to skip. Capped so a line cannot go below zero."
            literal :lineTaxRateField, default: "", group: :advanced,
                    description: "Optional key for a per-line tax-rate percent that overrides taxRate, such as tax_rate. Leave blank to use the order tax rate on every line."
            enum :discountType, DISCOUNT_TYPES, default: "none",
                 description: "Order-level discount applied after line discounts. none skips it. percent takes discountValue as 0-100 of remaining line nets. amount takes discountValue as a money amount split across lines pro rata (largest remainder) and never pushes a line below zero."
            decimal :discountValue, default: 0, min: 0, visible: { discountType: %w[percent amount] },
                    description: "Percent (0-100) or money amount according to discountType, such as 10. Overridden at runtime when discountVariable is set. Ignored when discountType is none."
            input :discountVariable, example: "coupon_amount", group: :advanced,
                  visible: { discountType: %w[percent amount] },
                  description: "Optional ctx path whose numeric value overrides discountValue at runtime, such as coupon_amount from a redeemed coupon. Leave blank to use discountValue."
            enum :taxMode, TAX_MODES, default: "exclusive",
                 description: "When tax is applied, after discounts. exclusive adds tax on top of payable (net x rate). inclusive extracts tax from the entered payable (price already includes tax). none skips tax and shippingTaxable."
            decimal :taxRate, default: 0, min: 0, max: 100, visible: { taxMode: %w[exclusive inclusive] },
                    description: "Order-level tax rate as a percent (0-100), such as 13 for 13 percent VAT. A line tax-rate field overrides this per line. Ignored when taxMode is none."
            decimal :shippingAmount, default: 0, min: 0,
                    description: "Shipping amount added after tax on merchandise, in the same units as line prices, such as 10. Overridden at runtime when shippingVariable is set. 0 means no shipping."
            input :shippingVariable, group: :advanced,
                  description: "Optional ctx path whose numeric value overrides shippingAmount at runtime, such as shipping from a rate lookup. Leave blank to use shippingAmount."
            flag :shippingTaxable, default: false, visible: { taxMode: %w[exclusive inclusive] },
                 description: "When on, shipping is taxed with the order taxRate and taxMode (exclusive adds tax on shipping; inclusive treats shippingAmount as tax-inclusive). Off (default) leaves shipping untaxed."
            integer :precision, min: 0, max: 6, default: 2,
                    description: "Decimal places for every amount (0-6). Use 2 for CNY/USD. Combined with roundPer to decide whether each line or only the order totals are rounded."
            enum :roundingMode, ROUNDING_MODES, default: "half_up",
                 description: "How amounts are rounded at the chosen precision. half_up is ordinary rounding; half_even is banker's rounding; floor/ceiling always go down/up."
            enum :roundPer, ROUND_PER, default: "line",
                 description: "line (default) rounds each line's net/tax/total then sums. total keeps line math exact and rounds only the order subtotal, discount, tax, shipping, and total."
            literal :currency, default: "", group: :advanced,
                    description: "Optional ISO 4217 code echoed into the result, such as CNY. Not used for conversion or rounding; set it so later steps (request_payment) can read pricing.currency."
            output :resultVar, default: "pricing",
                   description: "Ctx variable for the pricing hash. Amounts are decimal strings at the chosen precision (for example \"10.00\"). Keys: lines, subtotal, discount, tax, shipping, total, currency."
          end

          def generate_body
            attempt('"calculate_pricing.failed"', FlowchartRuntime::Pricing::Error) do
              [
                "pricing = FlowchartRuntime::Pricing.calculate(ctx, #{pricing_args})",
                assign(:resultVar, "pricing")
              ]
            end
          end

          private

          def pricing_args
            discounted = %w[percent amount].include?(value(:discountType).to_s)
            taxed = %w[exclusive inclusive].include?(value(:taxMode).to_s)
            [
              "lines: #{read(:sourceVariable)}",
              "quantity_field: #{read(:quantityField)}",
              "unit_price_field: #{read(:unitPriceField)}",
              ("line_discount_field: #{read(:lineDiscountField)}" if value(:lineDiscountField).to_s.strip.present?),
              ("line_tax_rate_field: #{read(:lineTaxRateField)}" if value(:lineTaxRateField).to_s.strip.present?),
              ("discount_type: #{read(:discountType)}" unless value(:discountType).to_s == "none"),
              ("discount_value: #{read(:discountValue)}" if discounted && !value(:discountValue).to_f.zero?),
              ("discount_override: #{read(:discountVariable)}" if discounted && value(:discountVariable).to_s.strip.present?),
              ("tax_mode: #{read(:taxMode)}" unless value(:taxMode).to_s == "exclusive"),
              ("tax_rate: #{read(:taxRate)}" if taxed && !value(:taxRate).to_f.zero?),
              ("shipping_amount: #{read(:shippingAmount)}" unless value(:shippingAmount).to_f.zero?),
              ("shipping_override: #{read(:shippingVariable)}" if value(:shippingVariable).to_s.strip.present?),
              ("shipping_taxable: #{read(:shippingTaxable)}" if taxed && value(:shippingTaxable)),
              ("precision: #{read(:precision)}" unless value(:precision) == 2),
              ("rounding_mode: #{read(:roundingMode)}" unless value(:roundingMode).to_s == "half_up"),
              ("round_per: #{read(:roundPer)}" unless value(:roundPer).to_s == "line"),
              ("currency: #{read(:currency)}" if value(:currency).to_s.strip.present?)
            ].compact.join(", ")
          end
        end
      end
    end
  end
end
