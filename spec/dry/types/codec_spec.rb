# frozen_string_literal: true

RSpec.describe Dry::Types::Codec do
  subject(:decimal) do
    Dry::Types::Codec.new(
      Dry::Types["strict.decimal"],
      external: Dry::Types["strict.string"],
      encoder: -> decimal { decimal.to_s("F") },
      fn: -> string { BigDecimal(string) }
    )
  end
  subject(:decimal) do
    Dry::Types::Codec.new(
      Dry::Types["strict.decimal"],
      external: Dry::Types["strict.string"],
      encoder: -> decimal { decimal.to_s("F") },
      fn: -> string { BigDecimal(string) }
    )
  end

  let(:date) do
    Dry::Types::Codec.new(
      Dry::Types["strict.date"],
      external: Dry::Types["strict.string"].constrained(format: /\A\d{4}-\d{2}-\d{2}\z/),
      encoder: -> date { date.iso8601 },
      fn: -> string { Date.iso8601(string) }
    )
  end

  describe ".new" do
    it "builds a codec from types" do
      expect(decimal.("12.34")).to eql(BigDecimal("12.34"))
    end

    it "builds a codec from primitive classes" do
      codec = Dry::Types::Codec.new(
        BigDecimal,
        external: String,
        encoder: -> decimal { decimal.to_s("F") },
        fn: -> string { BigDecimal(string) }
      )

      expect(codec.("1.5")).to eql(BigDecimal("1.5"))
      expect(codec.encode(BigDecimal("1.5"))).to eql("1.5")
    end

    it "accepts a block as the decoder" do
      codec = Dry::Types::Codec.new(
        Dry::Types["strict.decimal"],
        external: Dry::Types["strict.string"],
        encoder: -> decimal { decimal.to_s("F") }
      ) { |string| BigDecimal(string) }

      expect(codec.("1.5")).to eql(BigDecimal("1.5"))
    end

    it "raises an error when no decoder is given" do
      expect {
        Dry::Types::Codec.new(
          Dry::Types["strict.decimal"],
          external: Dry::Types["strict.string"],
          encoder: -> decimal { decimal.to_s("F") }
        )
      }.to raise_error(ArgumentError)
    end
  end

  describe "builder methods" do
    it "builds a codec with Types.Codec" do
      types = Dry.Types()

      codec = types.Codec(
        types.Instance(BigDecimal),
        external: types::Strict::String,
        encoder: -> decimal { decimal.to_s("F") },
        decoder: -> string { BigDecimal(string) }
      )

      expect(codec).to be_a(Dry::Types::Codec)
      expect(codec.("1.5")).to eql(BigDecimal("1.5"))
      expect(codec.encode(BigDecimal("1.5"))).to eql("1.5")
    end

    it "builds a codec with #codec on an existing type" do
      codec = Dry::Types["strict.decimal"].codec(
        external: Dry::Types["strict.string"],
        encoder: -> decimal { decimal.to_s("F") }
      ) { |string| BigDecimal(string) }

      expect(codec).to be_a(Dry::Types::Codec)
      expect(codec.("1.5")).to eql(BigDecimal("1.5"))
    end
  end

  describe "#call (decode)" do
    it "decodes the external representation into an internal value" do
      expect(decimal.("12.34")).to eql(BigDecimal("12.34"))
    end

    it "validates the input against the external type" do
      expect { decimal.(12.34) }.to raise_error(Dry::Types::CodecError, /decode failed/)
    end

    it "raises a CodecError with the decode direction when decoding fails" do
      expect { decimal.("not a number") }.to raise_error(Dry::Types::CodecError) { |error|
        expect(error.direction).to be(:decode)
        expect(error.path).to eql([])
      }
    end

    it "checks the input against the external constraint" do
      expect { date.("10/07/2026") }.to raise_error(Dry::Types::CodecError) { |error|
        expect(error.direction).to be(:decode)
      }
    end

    it "returns a failure result with a CodecError from #try" do
      result = decimal.try("not a number")

      expect(result).to be_failure
      expect(result.error).to be_a(Dry::Types::CodecError)
      expect(result.error.direction).to be(:decode)
    end

    it "yields to the block on failure when called with a block" do
      yielded = false
      decimal.("not a number") { yielded = true }

      expect(yielded).to be(true)
    end
  end

  describe "#encode" do
    it "encodes an internal value to its external representation" do
      expect(decimal.encode(BigDecimal("12.34"))).to eql("12.34")
    end

    it "encodes dates to their ISO 8601 representation" do
      expect(date.encode(Date.new(2026, 10, 7))).to eql("2026-10-07")
    end

    it "checks the internal value against the internal type" do
      expect { decimal.encode("12.34") }.to raise_error(Dry::Types::CodecError) { |error|
        expect(error.direction).to be(:encode)
        expect(error.path).to eql([])
      }
    end

    it "checks the encoder output against the external type" do
      codec = Dry::Types::Codec.new(
        Dry::Types["strict.decimal"],
        external: Dry::Types["strict.string"],
        encoder: -> decimal { decimal.to_i },
        fn: -> string { BigDecimal(string) }
      )

      expect { codec.encode(BigDecimal("1.5")) }.to raise_error(Dry::Types::CodecError) { |error|
        expect(error.direction).to be(:encode)
      }
    end

    it "returns a failure result with a CodecError from #try_encode" do
      result = decimal.try_encode("12.34")

      expect(result).to be_failure
      expect(result.error).to be_a(Dry::Types::CodecError)
      expect(result.error.direction).to be(:encode)
    end

    it "returns a success result from #try_encode" do
      result = decimal.try_encode(BigDecimal("12.34"))

      expect(result).to be_success
      expect(result.input).to eql("12.34")
    end
  end

  describe "round trips" do
    it "decode(encode(value)) equals the original value without sharing identity" do
      value = BigDecimal("12.34")
      round_tripped = decimal.(decimal.encode(value))

      expect(round_tripped).to eql(value)
      expect(round_tripped).not_to be(value)
    end

    it "encode(decode(representation)) equals the canonical representation" do
      expect(decimal.encode(decimal.("12.34"))).to eql("12.34")
    end

    it "canonicalizes representations as declared by the codec" do
      expect(decimal.encode(decimal.("12.340"))).to eql("12.34")
      expect(decimal.(decimal.encode(decimal.("12.340")))).to eql(decimal.("12.340"))
    end

    it "round trips dates" do
      expect(date.encode(date.("2026-10-07"))).to eql("2026-10-07")
      expect(date.(date.encode(Date.new(2026, 10, 7)))).to eql(Date.new(2026, 10, 7))
    end
  end

  describe "composition with arrays" do
    subject(:decimals) { Dry::Types["strict.array"].of(decimal) }

    it "decodes each member" do
      expect(decimals.(["1.0", "2.5"])).to eql([BigDecimal("1.0"), BigDecimal("2.5")])
    end

    it "encodes each member" do
      expect(decimals.encode([BigDecimal("1.0"), BigDecimal("2.5")])).to eql(["1.0", "2.5"])
    end

    it "keeps the member index and direction in decode errors" do
      expect { decimals.(["1.0", 2.5]) }.to raise_error(Dry::Types::CodecError) { |error|
        expect(error.direction).to be(:decode)
        expect(error.path).to eql([1])
        expect(error.message).to include("$[1]")
      }
    end

    it "keeps the member index and direction in encode errors" do
      expect { decimals.encode([BigDecimal("1.0"), "2.5"]) }
        .to raise_error(Dry::Types::CodecError) { |error|
          expect(error.direction).to be(:encode)
          expect(error.path).to eql([1])
          expect(error.message).to include("$[1]")
        }
    end

    it "keeps the member index in try failures" do
      result = decimals.try(["1.0", 2.5])

      expect(result).to be_failure
      expect(result.error.path).to eql([1])
    end
  end

  describe "composition with hash schemas" do
    subject(:schema) do
      Dry::Types["hash"].schema(
        amount: decimal,
        note: Dry::Types["strict.string"].default("n/a".freeze)
      )
    end

    it "decodes each key" do
      expect(schema.(amount: "3.14")).to eql(amount: BigDecimal("3.14"), note: "n/a")
    end

    it "encodes each key" do
      expect(schema.encode(amount: BigDecimal("3.14"), note: "hi"))
        .to eql(amount: "3.14", note: "hi")
    end

    it "evaluates and encodes defaults for missing keys" do
      expect(schema.encode(amount: BigDecimal("3.14"))).to eql(amount: "3.14", note: "n/a")
    end

    it "skips keys that are not required" do
      schema = Dry::Types["hash"].schema(
        amount: decimal,
        note?: Dry::Types["strict.string"]
      )

      expect(schema.encode(amount: BigDecimal("3.14"))).to eql(amount: "3.14")
    end

    it "raises a CodecError for missing required keys" do
      expect { schema.encode(note: "hi") }.to raise_error(Dry::Types::CodecError) { |error|
        expect(error.direction).to be(:encode)
        expect(error.path).to eql([:amount])
      }
    end

    it "keeps the key name and direction in decode errors" do
      expect { schema.(amount: 3.14) }.to raise_error(Dry::Types::CodecError) { |error|
        expect(error.direction).to be(:decode)
        expect(error.path).to eql([:amount])
        expect(error.message).to include("$.amount")
      }
    end

    it "keeps the key name and direction in encode errors" do
      expect { schema.encode(amount: "3.14") }.to raise_error(Dry::Types::CodecError) { |error|
        expect(error.direction).to be(:encode)
        expect(error.path).to eql([:amount])
      }
    end

    it "keeps the full path in nested structures" do
      schema = Dry::Types["hash"].schema(
        items: Dry::Types["strict.array"].of(
          Dry::Types["hash"].schema(price: decimal)
        )
      )

      expect { schema.encode(items: [{price: BigDecimal("1")}, {price: "2"}]) }
        .to raise_error(Dry::Types::CodecError) { |error|
          expect(error.direction).to be(:encode)
          expect(error.path).to eql([:items, 1, :price])
          expect(error.message).to include("$.items[1].price")
        }

      expect { schema.(items: [{price: "1"}, {price: 2}]) }
        .to raise_error(Dry::Types::CodecError) { |error|
          expect(error.direction).to be(:decode)
          expect(error.path).to eql([:items, 1, :price])
        }
    end
  end

  describe "composition with sum types" do
    let(:create_message) do
      Dry::Types["hash"].schema(
        type: Dry::Types["strict.string"].constrained(eql: "create"),
        amount: decimal
      )
    end

    let(:update_message) do
      Dry::Types["hash"].schema(
        type: Dry::Types["strict.string"].constrained(eql: "update"),
        amount: decimal
      )
    end

    subject(:message) { create_message | update_message }

    it "decodes each branch" do
      expect(message.(type: "create", amount: "1.5"))
        .to eql(type: "create", amount: BigDecimal("1.5"))
      expect(message.(type: "update", amount: "2.5"))
        .to eql(type: "update", amount: BigDecimal("2.5"))
    end

    it "encodes through the single accepting branch" do
      expect(message.encode(type: "create", amount: BigDecimal("1.5")))
        .to eql(type: "create", amount: "1.5")
      expect(message.encode(type: "update", amount: BigDecimal("2.5")))
        .to eql(type: "update", amount: "2.5")
    end

    it "raises a CodecError when no branch accepts the value" do
      expect { message.encode(type: "delete", amount: BigDecimal("1.5")) }
        .to raise_error(Dry::Types::CodecError) { |error|
          expect(error.direction).to be(:encode)
        }
    end

    context "with structurally similar branches" do
      let(:create_message) do
        Dry::Types["hash"].schema(
          type: Dry::Types["strict.string"],
          amount: decimal
        )
      end

      let(:update_message) do
        Dry::Types["hash"].schema(
          type: Dry::Types["strict.string"],
          amount: decimal
        )
      end

      it "raises an AmbiguousEncodingError instead of relying on branch order" do
        expect { message.encode(type: "create", amount: BigDecimal("1.5")) }
          .to raise_error(Dry::Types::AmbiguousEncodingError) { |error|
            expect(error.direction).to be(:encode)
          }
      end

      it "uses explicit tags to pick a branch" do
        tagged = create_message.tagged("create") | update_message.tagged("update")

        expect(tagged.encode(type: "create", amount: BigDecimal("1.5")))
          .to eql(type: "create", amount: "1.5")
        expect(tagged.encode(type: "update", amount: BigDecimal("2.5")))
          .to eql(type: "update", amount: "2.5")
      end

      it "raises an AmbiguousEncodingError when the value carries no matching tag" do
        tagged = create_message.tagged("create") | update_message.tagged("update")

        expect { tagged.encode(type: "delete", amount: BigDecimal("1.5")) }
          .to raise_error(Dry::Types::AmbiguousEncodingError)
      end

      it "reads tags from a custom key" do
        create = create_message.tagged("create", key: :kind)
        update = update_message.tagged("update", key: :kind)
        tagged = create | update

        expect(tagged.encode(kind: "create", type: "ignored", amount: BigDecimal("1.5")))
          .to eql(type: "ignored", amount: "1.5")
      end
    end
  end

  describe "mixing with other types" do
    it "raises a CodecError when encoding through a one-way constructor" do
      expect { Dry::Types["params.integer"].encode("1") }
        .to raise_error(Dry::Types::CodecError, /one-way constructor/) { |error|
          expect(error.direction).to be(:encode)
        }
    end

    it "encodes plain types as validated identity" do
      expect(Dry::Types["strict.integer"].encode(1)).to eql(1)
      expect { Dry::Types["strict.integer"].encode("1") }
        .to raise_error(Dry::Types::ConstraintError)
    end

    it "keeps the path when a one-way constructor is nested in a schema" do
      schema = Dry::Types["hash"].schema(age: Dry::Types["params.integer"])

      expect { schema.encode(age: 1) }.to raise_error(Dry::Types::CodecError) { |error|
        expect(error.direction).to be(:encode)
        expect(error.path).to eql([:age])
      }
    end

    it "encodes optional codecs" do
      optional = decimal.optional

      expect(optional.encode(nil)).to be_nil
      expect(optional.encode(BigDecimal("1.5"))).to eql("1.5")
      expect(optional.(nil)).to be_nil
      expect(optional.("1.5")).to eql(BigDecimal("1.5"))
    end

    it "uses internal values as defaults" do
      with_default = decimal.default(BigDecimal("0").freeze)

      expect(with_default.()).to eql(BigDecimal("0"))
      expect(with_default.encode(BigDecimal("0"))).to eql("0.0")
    end

    it "checks defaults against the internal constraint" do
      expect { decimal.default("0".freeze) }.to raise_error(Dry::Types::ConstraintError)
    end

    it "uses internal values as fallbacks" do
      with_fallback = decimal.fallback(BigDecimal("0").freeze)

      expect(with_fallback.("not a number")).to eql(BigDecimal("0"))
      expect(with_fallback.("1.5")).to eql(BigDecimal("1.5"))
      expect(with_fallback.encode(BigDecimal("1.5"))).to eql("1.5")
    end

    it "checks fallbacks against the internal constraint" do
      expect { decimal.fallback("0".freeze) }.to raise_error(Dry::Types::ConstraintError)
    end

    it "builds lax codecs" do
      lax = decimal.lax

      expect(lax.("not a number")).to eql("not a number")
      expect(lax.encode("not a decimal")).to eql("not a decimal")
      expect(lax.encode(BigDecimal("1.5"))).to eql("1.5")
    end

    it "keeps being a codec when meta is added" do
      codec = decimal.meta(source: "json")

      expect(codec).to be_a(Dry::Types::Codec)
      expect(codec.meta).to eql(source: "json")
      expect(codec.encode(BigDecimal("1.5"))).to eql("1.5")
    end

    it "keeps being a codec when a decoder is appended" do
      codec = decimal.constructor { |decimal| decimal.round(2) }

      expect(codec).to be_a(Dry::Types::Codec)
      expect(codec.("1.555")).to eql(BigDecimal("1.56"))
      expect(codec.encode(BigDecimal("1.555"))).to eql("1.555")
    end
  end

  describe "#inspect" do
    it "includes the codec signature" do
      expect(decimal.inspect).to include("Codec<")
      expect(decimal.inspect).to include("<=>")
    end
  end

  describe "#to_ast" do
    it "can be compiled back to an equal codec" do
      ast = decimal.to_ast
      compiled = Dry::Types::Compiler.new(Dry::Types).(ast)

      expect(compiled).to eql(decimal)
      expect(compiled.encode(BigDecimal("1.5"))).to eql("1.5")
    end
  end
end
