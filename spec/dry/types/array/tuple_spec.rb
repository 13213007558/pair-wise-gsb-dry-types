# frozen_string_literal: true

RSpec.describe Dry::Types::Array::Tuple do
  subject(:tuple) do
    Dry::Types["nominal.array"].tuple(
      Dry::Types["strict.string"],
      rest: Dry::Types["coercible.integer"],
      tail: [Dry::Types["strict.hash"].default({}.freeze)]
    )
  end

  it "coerces a command name, variadic numeric values, and an options hash" do
    expect(tuple.(["sum", "1", 2, {format: "json"}])).to eql(
      ["sum", 1, 2, {format: "json"}]
    )
  end

  it "coerces the outer array before applying tuple slots" do
    array_with_constructor = Dry::Types["nominal.array"].constructor do |input|
      input.is_a?(::Array) ? input : input.split("|")
    end
    params_tuple = array_with_constructor.tuple(
      Dry::Types["strict.string"],
      rest: Dry::Types["coercible.integer"]
    )

    expect(params_tuple.("sum|1")).to eql(["sum", 1])
  end

  it "fills an absent options hash from the tail default" do
    expect(tuple.(["sum", "1", 2])).to eql(["sum", 1, 2, {}])
  end

  it "checks length before coercing members" do
    result = tuple.try([])

    expect(result).to be_failure
    expect(result.input).to eql([])
    expect(result.error.message).to include("expected at least 1")
  end

  it "rejects a non-array input before touching slots" do
    result = tuple.try("not-an-array")

    expect(result).to be_failure
    expect(result.input).to eql("not-an-array")
  end

  it "does not invoke constructors when the length is invalid" do
    called = false
    integer = Dry::Types["nominal.integer"].constructor do |input|
      called = true
      Integer(input)
    end
    short_tuple = Dry::Types["nominal.array"].tuple(
      Dry::Types["strict.string"],
      rest: integer,
      suffix: Dry::Types["strict.hash"]
    )

    result = short_tuple.try(["sum"])

    expect(result).to be_failure
    expect(called).to be(false)
  end

  it "does not invoke constructors while choosing a tail allocation" do
    calls = []
    integer = Dry::Types["nominal.integer"].constructor do |input|
      calls << input
      Integer(input)
    end
    hash = Dry::Types["strict.hash"].default({}.freeze)
    allocating_tuple = Dry::Types["nominal.array"].tuple(
      Dry::Types["strict.string"],
      rest: integer,
      tail: [hash]
    )

    expect(allocating_tuple.(["sum", "1", {}])).to eql(["sum", 1, {}])
    expect(calls).to eql(["1"])
  end

  it "preserves the original input index of a failed rest slot" do
    result = tuple.try(["sum", "1", "bad", {format: "json"}])

    expect(result).to be_failure
    expect(result.input).to eql(["sum", 1])
    expect(result.error.meta).to eql(index: 2)
  end

  it "preserves the original input index of a failed present tail slot" do
    result = tuple.try(["sum", "1", 2, "options"])

    expect(result).to be_failure
    expect(result.input).to eql(["sum", 1, 2])
    expect(result.error.meta).to eql(index: 3)
  end

  it "supports safe partial coercion" do
    expect(tuple.(["sum", "1", "bad", {}]) { |output| output }).to eql(["sum", 1])
  end

  it "coerces fixed suffixes after the rest slot" do
    suffix_tuple = Dry::Types["nominal.array"].tuple(
      Dry::Types["strict.string"],
      rest: Dry::Types["coercible.integer"],
      suffix: Dry::Types["strict.symbol"]
    )

    expect(suffix_tuple.(["sum", "1", 2, :done])).to eql(["sum", 1, 2, :done])
    expect(suffix_tuple.(["sum", :done])).to eql(["sum", :done])

    result = suffix_tuple.try(["sum", "1", "bad"])
    expect(result.error.meta).to eql(index: 2)
  end

  it "keeps fixed suffixes before optional tail slots" do
    anchored_tuple = Dry::Types["nominal.array"].tuple(
      Dry::Types["strict.string"],
      rest: Dry::Types["coercible.integer"],
      suffix: Dry::Types["strict.hash"],
      tail: [
        Dry::Types["strict.symbol"].default(:text),
        Dry::Types["strict.bool"].default(false)
      ]
    )

    expect(anchored_tuple.(["sum", "1", 2, {format: "json"}, :compact, true])).to eql(
      ["sum", 1, 2, {format: "json"}, :compact, true]
    )
  end

  it "recompiles from AST with identical semantics" do
    recompiled = Dry::Types::Compiler.new(Dry::Types).(tuple.to_ast)

    expect(recompiled.to_ast).to eql(tuple.to_ast)
    expect(recompiled.(["sum", "1", 2, {}])).to eql(tuple.(["sum", "1", 2, {}]))
  end

  it "recompiles a callable tail default from AST" do
    callable_tuple = Dry::Types["nominal.array"].tuple(
      Dry::Types["strict.string"],
      rest: Dry::Types["coercible.integer"],
      tail: [Dry::Types["strict.hash"].default { {generated: true} }]
    )
    recompiled = Dry::Types::Compiler.new(Dry::Types).(callable_tuple.to_ast)

    expect(recompiled.(["sum", 1])).to eql(["sum", 1, {generated: true}])
  end

  it "rejects non-default tail slots at definition time" do
    expect {
      Dry::Types["nominal.array"].tuple(
        Dry::Types["strict.string"],
        tail: [Dry::Types["strict.symbol"]]
      )
    }.to raise_error(ArgumentError, "tuple tail slots must provide defaults")
  end

  it "rejects too many slots when there is no rest type" do
    fixed_tuple = Dry::Types["nominal.array"].tuple(
      Dry::Types["strict.string"],
      tail: [Dry::Types["strict.symbol"].default(:none)]
    )

    result = fixed_tuple.try(["sum", :one, :two])

    expect(result).to be_failure
    expect(result.error.message).to include("expected 1..2")
  end
end
