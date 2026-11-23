# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Mask do
  describe ".apply" do
    it "dispatches last4, email and custom regex" do
      expect(described_class.apply("4111111111111234", type: "last4")).to eq("************1234")
      expect(described_class.apply("ada@example.test", type: "email")).to eq("a**@example.test")
      expect(described_class.apply("abc123", type: "custom", regex_pattern: "\\d+")).to eq("abc*")
    end

    it "masks names and addresses" do
      expect(described_class.apply("Jane Doe", type: "name")).to eq("J*** D**")
      expect(described_class.apply("123 Main St, Springfield IL 62701", type: "address"))
        .to eq("*** **** **, Springfield IL 62701")
    end

    it "rejects an unknown type" do
      expect { described_class.apply("x", type: "unknown") }
        .to raise_error(described_class::Error, /unsupported mask type/)
    end
  end

  describe ".credit_card" do
    it "reveals the BIN and the last four digits, preserving separators" do
      expect(described_class.credit_card("4111-1111-1111-1234")).to eq("4111-11**-****-1234")
    end

    it "reveals the BIN and the last four digits without separators" do
      expect(described_class.credit_card("4111111111111234")).to eq("411111******1234")
    end

    it "strips separators when preserve_format is false" do
      expect(described_class.credit_card("4111-1111-1111-1234", preserve_format: false))
        .to eq("411111******1234")
    end

    it "suppresses the BIN window for a PAN too short to keep a masked middle" do
      expect(described_class.credit_card("411111234")).to eq("*****1234")
    end

    it "honors a custom mask character" do
      expect(described_class.credit_card("4111111111111234", mask_char: "X"))
        .to eq("411111XXXXXX1234")
    end

    it "does not raise on an empty value" do
      expect(described_class.credit_card("")).to eq("")
    end
  end

  describe ".ssn" do
    it "reveals only the last four digits and keeps the dashes" do
      expect(described_class.ssn("123-45-6789")).to eq("***-**-6789")
    end

    it "never reveals a leading window the way credit_card does" do
      expect(described_class.ssn("4111111111111234")).to eq("************1234")
    end

    it "drops separators when preserve_format is false" do
      expect(described_class.ssn("123-45-6789", preserve_format: false)).to eq("*****6789")
    end

    it "leaves a value shorter than the tail window untouched" do
      expect(described_class.ssn("12")).to eq("12")
    end
  end

  describe ".phone" do
    it "reveals the last four digits and keeps grouping separators" do
      expect(described_class.phone("(415) 555-1234")).to eq("(***) ***-1234")
    end

    it "keeps a delimited international dialling prefix visible" do
      expect(described_class.phone("+1 (415) 555-1234")).to eq("+1 (***) ***-1234")
      expect(described_class.phone("+44-20-7946-1234")).to eq("+44-**-****-1234")
    end

    it "does not guess a country code when the prefix is not delimited" do
      expect(described_class.phone("+14155551234")).to eq("+*******1234")
    end

    it "drops separators when preserve_format is false" do
      expect(described_class.phone("(415) 555-1234", preserve_format: false)).to eq("******1234")
    end
  end

  describe ".mobile" do
    it "keeps the first three and last four digits of a mainland mobile number" do
      expect(described_class.mobile("13812345678")).to eq("138****5678")
      expect(described_class.mobile("138-1234-5678")).to eq("138-****-5678")
    end
  end

  describe ".id_number" do
    it "keeps the region (first six) and last four of an 18-character resident ID" do
      expect(described_class.id_number("11010119900101123X")).to eq("110101********123X")
    end
  end

  describe "the three formats are genuinely distinct" do
    let(:pan) { "4111-1111-1111-1234" }

    it "masks the same PAN differently per convention" do
      results = [
        described_class.credit_card(pan),
        described_class.ssn(pan),
        described_class.phone("+1 #{pan}")
      ]
      expect(results.uniq.size).to eq(3)
    end
  end

  describe ".window" do
    it "keeps the requested significant characters at each end" do
      expect(described_class.window("abcdefghij", visible_start: 2, visible_end: 3,
                                    preserve_format: false)).to eq("ab*****hij")
    end

    it "does not count separators towards the window when preserving format" do
      expect(described_class.window("4111-1111-1111-1234", visible_end: 4))
        .to eq("****-****-****-1234")
    end

    it "clamps a window wider than the value" do
      expect(described_class.window("ab", visible_end: 4)).to eq("ab")
      expect(described_class.window("", visible_end: 4)).to eq("")
    end

    it "never lets overlapping windows reveal more than the value" do
      expect(described_class.window("abcd", visible_start: 3, visible_end: 3)).to eq("abcd")
    end

    it "rejects a negative window" do
      expect { described_class.window("abc", visible_start: -1) }
        .to raise_error(described_class::Error, /visible_start/)
    end

    it "rejects a non-integer window" do
      expect { described_class.window("abc", visible_end: "x") }
        .to raise_error(described_class::Error, /visible_end/)
    end

    it "rejects an empty mask character" do
      expect { described_class.window("abc", mask_char: "") }
        .to raise_error(described_class::Error, /mask character/)
    end
  end
end
