# frozen_string_literal: true

require "dry-types"

RSpec.describe Dry::Types::Codec do
  subject(:types) { Dry::Types }

  let(:money_codec) do
    external = types["nominal.string"].constrained(
      format: /\A-?\d+(?:\.\d{1,2})?\z/
    )
    internal = types["nominal.decimal"]

    external.codec(
      internal,
      decode: -> value { BigDecimal(value) },
      encode: -> value {
        unless value.is_a?(BigDecimal) && value.finite? && value == value.truncate(2)
          raise Dry::Types::CodecError, "internal value must be a decimal with at most two digits"
        end

        value.to_s("F")
      }
    )
  end

  let(:date_codec) do
    external = types["nominal.string"].constrained(format: /\A\d{4}-\d{2}-\d{2}\z/)
    external.codec(
      types["nominal.date"],
      decode: Date.method(:parse),
      encode: -> date { date.iso8601 }
    )
  end

  FixedAmount = Data.define(:amount)
  Percentage = Data.define(:fraction)

  let(:message_codec) do
    external = types["nominal.hash"].schema(
      amount: money_codec
    )
    external.codec(
      types["nominal.any"],
      decode: -> payload {
        FixedAmount.new(amount: payload.fetch(:amount))
      },
      encode: -> message {
        {amount: message.amount} if message.is_a?(FixedAmount)
      }
    )
  end

  let(:percentage_codec) do
    external = types["nominal.hash"].schema(
      fraction: money_codec
    )

    external.codec(
      types["nominal.any"],
      decode: -> payload {
        Percentage.new(fraction: payload.fetch(:fraction))
      },
      encode: -> message { {fraction: message.fraction} }
    )
  end

  it "round-trips decimal fixed-point values through a declared codec" do
    expect(Dry::Types::Codec.new(
      types["strict.string"],
      types["strict.integer"],
      decoder: :to_i.to_proc,
      encoder: :to_s.to_proc
    ).decode("1")).to eq(1)

    decoded = money_codec.decode("1.20")

    expect(decoded).to eq(BigDecimal("1.20"))
    expect(money_codec.encode(decoded)).to eq("1.2")
    expect(money_codec.encode(money_codec.decode("1.20"))).to eq("1.2")
  end

  it "checks both external and internal constraints" do
    expect { money_codec.decode("1.234") }
      .to raise_error(Dry::Types::CodecError, /decode error.*1\.234/)

    expect { money_codec.encode(BigDecimal("1.234")) }
      .to raise_error(Dry::Types::CodecError, /encode error.*at most two digits/)
  end

  it "round-trips dates without implying Date identity" do
    payload = "2026-10-07"
    decoded = date_codec.decode(payload)

    expect(decoded).to eq(Date.new(2026, 10, 7))
    expect(decoded).not_to equal(Date.new(2026, 10, 7))
    expect(date_codec.encode(decoded)).to eq(payload)
  end

  it "combines codecs with arrays and hash schemas" do
    list = types["nominal.array"].of(date_codec)
    schema = types["nominal.hash"].schema(
      dates: list,
      amount: money_codec
    )

    payload = {dates: ["2026-10-07"], amount: "10.50"}
    decoded = schema.decode(payload)

    expect(decoded).to eq(dates: [Date.new(2026, 10, 7)], amount: BigDecimal("10.50"))
    expect(schema.encode(decoded)).to eq(dates: ["2026-10-07"], amount: "10.5")
  end

  it "preserves paths and direction in nested decode and encode errors" do
    schema = types["nominal.hash"].schema(dates: types["nominal.array"].of(date_codec))

    expect { schema.decode({dates: ["2026-10-07", "bad-date"]}) }
      .to raise_error(Dry::Types::CodecError, /decode error: at :dates\.1/)

    expect { schema.encode({dates: ["not-a-date"]}) }
      .to raise_error(Dry::Types::CodecError, /encode error: at :dates\.0/)
  end

  it "applies defaults while decoding and omits defaults that are absent when encoding" do
    type = types["nominal.string"].codec(types["nominal.string"])
    schema = types["nominal.hash"].schema(
      name: type.default("anonymous"),
      note?: type
    )

    expect(schema.decode({})).to eq(name: "anonymous")
    expect(schema.encode({name: "Jane"})).to eq(name: "Jane")

    expect { schema.encode({}) }
      .to raise_error(Dry::Types::CodecError, /encode error.*:name.*missing/)
  end

  it "round-trips nil through optional codecs" do
    optional = date_codec.optional

    expect(optional.decode(nil)).to be_nil
    expect(optional.encode(nil)).to be_nil
    expect((date_codec | optional).encode(nil)).to be_nil
  end

  it "does not treat a one-way constructor as an encoder" do
    one_way = types["json.decimal"]
    schema = types["nominal.hash"].schema(amount: one_way)

    expect(schema.decode({amount: "1.2"})).to eq(amount: BigDecimal("1.2"))
    expect { schema.encode({amount: BigDecimal("1.2")}) }
      .to raise_error(Dry::Types::CodecError, /encode error: at :amount.*one-way/)

    nested = types["nominal.hash"].schema(
      amounts: types["nominal.array"].of(one_way)
    )

    expect { nested.encode({amounts: [BigDecimal("1.2")]}) }
      .to raise_error(Dry::Types::CodecError, /encode error: at :amounts[.]0.*one-way/)
  end

  it "round-trips structurally similar messages through explicit tagged branches" do
    sum = message_codec.tag("fixed") | percentage_codec.tag("percentage")

    fixed_payload = {type: "fixed", amount: "1.20"}
    percentage_payload = {type: "percentage", fraction: "0.15"}

    fixed = sum.decode(fixed_payload)
    percentage = sum.decode(percentage_payload)

    expect(fixed).to eq(FixedAmount.new(BigDecimal("1.20")))
    expect(percentage).to eq(Percentage.new(BigDecimal("0.15")))
    expect(sum.encode(fixed, as: "fixed")).to eq(fixed_payload.merge(amount: "1.2"))
    expect(sum.encode(percentage, as: "percentage")).to eq(percentage_payload)
  end

  it "rejects ambiguous sum encoding instead of choosing a branch by order" do
    shared_hash = types["nominal.hash"].schema(amount: money_codec)
    fixed = shared_hash.codec(
      types["nominal.any"],
      decode: -> payload { FixedAmount.new(amount: payload.fetch(:amount)) },
      encode: -> message { {amount: message.amount} if message.is_a?(FixedAmount) }
    ).tag("fixed")
    percentage = shared_hash.codec(
      types["nominal.any"],
      decode: -> payload { Percentage.new(fraction: payload.fetch(:amount)) },
      encode: -> message { {amount: message.fraction} }
    ).tag("percentage")
    value = FixedAmount.new(BigDecimal("1"))

    expect { (fixed | percentage).encode(value) }
      .to raise_error(Dry::Types::AmbiguousCodecError, /ambiguous encode.*fixed.*percentage/)
  end

  it "reports ambiguity when untagged sum branches both decode the same representation" do
    string = types["strict.string"]
    integer = types["strict.integer"]
    codec = string.codec(integer, decode: :to_i.to_proc, encode: :to_s.to_proc)

    expect { (codec | codec).decode("1") }
      .to raise_error(Dry::Types::AmbiguousCodecError, /ambiguous decode/)
  end
end
