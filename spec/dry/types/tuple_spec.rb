# frozen_string_literal: true

RSpec.describe Dry::Types::Tuple do
  let(:string) { Dry::Types["strict.string"] }
  let(:integer) { Dry::Types["strict.integer"] }
  let(:hash) { Dry::Types["nominal.hash"] }

  describe "definition" do
    it "rejects combining a rest type with optional trailing slots" do
      expect {
        Dry::Types["nominal.array"].tuple(
          string,
          rest: integer,
          optional: [hash]
        )
      }.to raise_error(ArgumentError, /ambiguous/)
    end

    it "resolves string identifiers for slots" do
      type = Dry::Types["nominal.array"].tuple("strict.string", tail: ["nominal.hash"])

      expect(type.head).to eql([string])
      expect(type.tail).to eql([hash])
    end
  end

  describe "command interface: head is a command name, tail is an options hash,
            middle is a variable number of numeric arguments" do
    subject(:command) do
      Dry::Types["nominal.array"].tuple(
        string,
        rest: Dry::Types["params.float"],
        tail: [hash]
      )
    end

    it "coerces the command name, numeric args and options hash" do
      expect(command.call(["move", "1.0", "2.5", {verbose: true}])).to eql(
        ["move", 1.0, 2.5, {verbose: true}]
      )
    end

    it "allows an empty rest section" do
      expect(command.call(["move", {verbose: true}])).to eql(["move", {verbose: true}])
    end

    it "raises a coercion error when the command name is missing" do
      expect { command.call([{verbose: true}]) }.to raise_error(
        Dry::Types::CoercionError,
        /at least 2 expected/
      )
    end

    it "checks the length before converting any member" do
      converted = 0
      counting = Dry::Types["nominal.string"].constructor { |input|
        converted += 1
        input
      }
      type = Dry::Types["nominal.array"].tuple(counting, rest: integer, tail: [hash])

      expect { type.call([]) }.to raise_error(Dry::Types::CoercionError, /at least 2/)
      expect(converted).to be(0)
    end
  end

  describe "slots with constructors, constraints and defaults" do
    subject(:type) do
      Dry::Types["nominal.array"].tuple(
        Dry::Types["coercible.integer"],
        Dry::Types["strict.integer"].constrained(gt: 0),
        optional: [Dry::Types["strict.integer"].default(10)],
        tail: []
      )
    end

    it "applies the slot constructor" do
      expect(type.call(["1", 2, 3])).to eql([1, 2, 3])
    end

    it "enforces the slot constraint" do
      expect { type.call([1, -2]) }.to raise_error(Dry::Types::ConstraintError)
    end

    it "fills in the default of an absent optional slot" do
      expect(type.call([1, 2])).to eql([1, 2, 10])
    end
  end

  describe "optional trailing slots" do
    subject(:type) do
      Dry::Types["nominal.array"].tuple(
        string,
        tail: [hash],
        optional: [integer, Dry::Types["strict.symbol"].default(:auto)]
      )
    end

    it "omits absent slots without defaults" do
      expect(type.call(["cmd", {}])).to eql(["cmd", {}, :auto])
    end

    it "binds present slots in order" do
      expect(type.call(["cmd", {}, 5])).to eql(["cmd", {}, 5, :auto])
      expect(type.call(["cmd", {}, 5, :manual])).to eql(["cmd", {}, 5, :manual])
    end

    it "rejects input longer than the maximum length" do
      expect { type.call(["cmd", {}, 5, :manual, :extra]) }.to raise_error(
        Dry::Types::CoercionError,
        /at most 4 expected/
      )
    end
  end

  describe "#try" do
    subject(:command) do
      Dry::Types["nominal.array"].tuple(
        string,
        rest: integer,
        tail: [hash]
      )
    end

    it "returns success for valid input" do
      result = command.try(["move", 1, 2, {}])

      expect(result).to be_success
      expect(result.input).to eql(["move", 1, 2, {}])
    end

    it "returns a failure for non-array input" do
      expect(command.try("move")).to be_failure
    end

    it "returns a length failure before trying members" do
      result = command.try([:not_a_string])

      expect(result).to be_failure
      expect(result.error.message).to match(/at least 2 expected/)
    end

    it "keeps the actual input index of the failing element" do
      result = command.try(["move", 1, "two", 3, {}])

      expect(result).to be_failure
      expect(result.error).to be_a(Dry::Types::TupleError)
      expect(result.error.index).to be(2)
    end

    it "keeps the actual input index with optional trailing slots" do
      type = Dry::Types["nominal.array"].tuple(
        string,
        tail: [hash],
        optional: [integer]
      )

      result = type.try(["cmd", {}, "nope"])

      expect(result).to be_failure
      expect(result.error.index).to be(2)
    end

    it "yields the failure to a block" do
      yielded = nil
      command.try(["move", "x", {}]) { |failure| yielded = failure }

      expect(yielded).to be_failure
      expect(yielded.error.index).to be(1)
    end
  end

  describe "#to_ast" do
    subject(:type) do
      Dry::Types["nominal.array"].tuple(
        string,
        rest: integer,
        tail: [hash]
      )
    end

    it "produces a tuple node" do
      expect(type.to_ast).to eql(
        [:tuple, [
          {
            head: [string.to_ast],
            rest: integer.to_ast,
            tail: [hash.to_ast],
            optional: []
          },
          {}
        ]]
      )
    end

    it "keeps the same semantics after recompilation" do
      compiled = Dry::Types::Compiler.new(Dry::Types).(type.to_ast)

      expect(compiled.call(["move", 1, 2, {}])).to eql(["move", 1, 2, {}])
      expect(compiled.try(["move", "x", {}]).error.index).to be(1)
      expect(compiled.try([1]).error.message).to match(/at least 2 expected/)
      expect(compiled.to_ast).to eql(type.to_ast)
    end

    it "keeps optional slots and defaults after recompilation" do
      type = Dry::Types["nominal.array"].tuple(
        string,
        tail: [hash],
        optional: [Dry::Types["strict.integer"].default(10)]
      )
      compiled = Dry::Types::Compiler.new(Dry::Types).(type.to_ast)

      expect(compiled.call(["cmd", {}])).to eql(["cmd", {}, 10])
      expect(compiled.call(["cmd", {}, 5])).to eql(["cmd", {}, 5])
    end
  end

  describe "#lax" do
    it "returns a lax tuple" do
      type = Dry::Types["nominal.array"].tuple(string, rest: integer, tail: [hash])
      lax = type.lax

      expect(lax.call(["cmd", 1, {}])).to eql(["cmd", 1, {}])
      expect(lax.call([:invalid, 1, {}])).to eql([:invalid, 1, {}])
    end
  end

  describe "#inspect" do
    it "renders the tuple structure" do
      type = Dry::Types["nominal.array"].tuple(
        Dry::Types["nominal.string"],
        rest: Dry::Types["nominal.integer"],
        tail: [Dry::Types["nominal.hash"]]
      )

      expect(type.inspect).to include("Tuple<")
    end
  end
end
