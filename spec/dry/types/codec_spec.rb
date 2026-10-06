# frozen_string_literal: true

RSpec.describe Dry::Types::Codec do
  subject(:payment_type) { fixed_payment | percentage_payment }

  let(:time_type) do
    Dry.Types::Nominal::Time.codec(
      lambda do |value|
        begin
          Time.iso8601(value)
        rescue ::ArgumentError
          raise Dry::Types::DecodingError, "invalid time"
        end
      end,
      -> value { value.utc.iso8601(3) }
    )
  end

  let(:amount_type) do
    Dry.Types::Nominal::Decimal.codec(
      -> value { BigDecimal(value) },
      -> value { format("%.2f", value.round(2)) }
    )
  end

  let(:line_item_type) do
    Dry.Types().Hash(
      amount: amount_type,
      paid_at: time_type
    )
  end

  let(:invoice_type) do
    Dry.Types().Hash(
      issued_at: time_type,
      lines: Dry.Types().Array(line_item_type),
      note: Dry.Types::Nominal::String.optional
    )
  end

  let(:fixed_payment) do
    Dry.Types().Hash(
      kind: Dry.Types::Nominal::String,
      amount: amount_type
    )
  end

  let(:percentage_payment) do
    Dry.Types().Hash(
      kind: Dry.Types::Nominal::String,
      percentage: Dry.Types::Nominal::Decimal
    )
  end

  let(:invoice) do
    {
      issued_at: "2026-10-06T08:30:00+08:00",
      lines: [
        {
          amount: "12.345",
          paid_at: "2026-10-06T01:02:03Z"
        }
      ],
      note: nil
    }
  end

  describe "#decode and #encode" do
    it "propagates through schemas, arrays, optionals and sums" do
      decoded = invoice_type.decode(invoice)

      expect(decoded).to eq(
        issued_at: Time.iso8601("2026-10-06T08:30:00+08:00"),
        lines: [
          {
            amount: BigDecimal("12.345"),
            paid_at: Time.iso8601("2026-10-06T01:02:03Z")
          }
        ],
        note: nil
      )

      expect(invoice_type.encode(decoded)).to eq(
        issued_at: "2026-10-06T00:30:00.000Z",
        lines: [
          {
            amount: "12.35",
            paid_at: "2026-10-06T01:02:03.000Z"
          }
        ],
        note: nil
      )
    end

    it "uses the declared encoder as the canonical output for non-injective decode" do
      decoded = amount_type.decode("12.300")

      expect(decoded).to eq(BigDecimal("12.3"))
      expect(amount_type.encode(decoded)).to eq("12.30")
      expect(amount_type.encode(amount_type.decode("12.300"))).to eq("12.30")
    end

    it "encodes the matching branch of a sum type" do
      decoded = payment_type.decode(kind: "fixed", amount: "19.999")

      expect(decoded).to eq(kind: "fixed", amount: BigDecimal("19.999"))
      expect(payment_type.encode(decoded)).to eq(kind: "fixed", amount: "20.00")
    end
  end

  describe "without an encoder" do
    it "does not invert a constructor proc and reports the type as non-encodable" do
      type = Dry.Types::Nominal::Integer.constructor { |value| Integer(value) }

      expect(type).not_to be_encodable
      expect {
        type.encode(12)
      }.to raise_error(
        Dry::Types::EncodingError,
        "encode failed at $: type has no encoder (register an explicit encoder with Codec)"
      )
    end

    it "does not treat a decode-only codec as encodable" do
      type = Dry.Types::Nominal::Time.codec(-> value { Time.iso8601(value) })

      expect(type).not_to be_encodable
      expect {
        type.encode(Time.now)
      }.to raise_error(Dry::Types::EncodingError, /encode failed at \$: type has no encoder/)
    end
  end

  describe "with an existing constructor" do
    it "uses the explicit encoder rather than inverting the constructor" do
      type = Dry.Types::Nominal::Integer
        .constructor { |value| Integer(value) }
        .codec(nil, -> value { value.to_s })

      expect(type.decode("42")).to eq(42)
      expect(type.encode(42)).to eq("42")
      expect(type).to be_encodable
    end
  end

  describe "path errors" do
    it "reports direction and schema/array path for decode failures" do
      invoice[:lines][0][:paid_at] = "not a time"

      expect {
        invoice_type.decode(invoice)
      }.to raise_error(Dry::Types::CodecError) do |error|
        expect(error.direction).to eq(:decode)
        expect(error.path).to eq([:lines, 0, :paid_at])
        expect(error.message).to eq("decode failed at $.lines[0].paid_at: invalid time")
      end
    end

    it "reports direction and nested schema path for encode failures" do
      decoded = invoice_type.decode(invoice)
      decoded[:lines][0][:amount] = "12.35"

      expect {
        invoice_type.encode(decoded)
      }.to raise_error(Dry::Types::CodecError) do |error|
        expect(error.direction).to eq(:encode)
        expect(error.path).to eq([:lines, 0, :amount])
        expect(error.message).to include("encode failed at $.lines[0].amount:")
        expect(error.message).to include("undefined method `round' for an instance of String")
      end
    end
    it "reports missing keys with the encoding direction" do
      expect {
        invoice_type.encode(issued_at: Time.now, lines: [])
      }.to raise_error(Dry::Types::EncodingError) do |error|
        expect(error.direction).to eq(:encode)
        expect(error.path).to eq([:note])
      end
    end
  end
end
