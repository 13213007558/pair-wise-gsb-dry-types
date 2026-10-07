# frozen_string_literal: true

RSpec.describe Dry::Types::Intersection do
  let(:t) { Dry.Types }

  let(:callable_type) { t.Interface(:call) }
  let(:procable_type) { t.Interface(:to_proc) }
  let(:function_type) { callable_type & procable_type }

  describe "common nominal behavior" do
    subject(:type) { function_type }

    it_behaves_like "Dry::Types::Nominal#meta"
    it_behaves_like "Dry::Types::Nominal without primitive"
    it_behaves_like "a composable constructor"

    it "is frozen" do
      expect(type).to be_frozen
    end
  end

  it_behaves_like "a constrained type" do
    let(:type) { function_type }

    it_behaves_like "a composable constructor"
  end

  describe "#[]" do
    it "works with two pass-through types" do
      type = t::Nominal::Hash & t.Hash(foo: t::Nominal::Integer)

      expect(type[{foo: ""}]).to eql({foo: ""})
      expect(type[{foo: 312}]).to eql({foo: 312})
    end

    it "works with two strict types" do
      type = t::Strict::Hash & t.Hash(foo: t::Strict::Integer)

      expect(type[{foo: 312}]).to eql({foo: 312})

      expect { type[312] }.to raise_error(Dry::Types::CoercionError)
    end

    it "is aliased as #call" do
      type = t::Nominal::Hash & t.Hash(foo: t::Nominal::Integer)

      expect(type.call({foo: ""})).to eql({foo: ""})
      expect(type.call({foo: 312})).to eql({foo: 312})
    end

    it "works with two constructor & constrained types" do
      left = t.Array(t::Strict::Hash)
      right = t.Array(t.Hash(foo: t::Nominal::Integer))

      type = left & right

      expect(type[[{foo: 312}]]).to eql([{foo: 312}])
    end

    it "works with two complex types with constraints" do
      type =
        t
          .Array(t.Array(t::Coercible::String.constrained(min_size: 5)).constrained(size: 2))
          .constrained(min_size: 1) &
        t
          .Array(t.Array(t::Coercible::String.constrained(format: /foo/)).constrained(size: 2))
          .constrained(min_size: 2)

      expect(type.([%w[foofoo barfoo], %w[bazfoo fooqux]])).to eql(
        [%w[foofoo barfoo], %w[bazfoo fooqux]]
      )

      expect { type[:oops] }.to raise_error(Dry::Types::ConstraintError, /:oops/)

      expect { type[[]] }.to raise_error(Dry::Types::ConstraintError, /\[\]/)

      expect { type.([%i[foo]]) }.to raise_error(Dry::Types::ConstraintError, /\[:foo\]/)

      expect { type.([[1], [2]]) }.to raise_error(Dry::Types::ConstraintError, /2, \[1\]/)

      expect { type.([%w[foofoo barfoo], %w[bazfoo foo]]) }.to raise_error(
        Dry::Types::ConstraintError,
        /min_size\?\(5, "foo"\)/
      )
    end
  end

  describe "#try" do
    subject(:type) { function_type }

    it "returns success when value passed" do
      expect(type.try(-> {})).to be_success
    end

    it "returns failure when value did not pass" do
      expect(type.try(:foo)).to be_failure
    end
  end

  describe "#success" do
    subject(:type) { function_type }

    it "returns success when value passed" do
      expect(type.success(-> {})).to be_success
    end

    it "raises ArgumentError when non of the types have a valid input" do
      expect { type.success("foo") }.to raise_error(ArgumentError, /Invalid success value 'foo' /)
    end
  end

  describe "#failure" do
    subject(:type) { Dry::Types["integer"] & Dry::Types["string"] }

    it "returns failure when invalid value is passed" do
      expect(type.failure(true)).to be_failure
    end
  end

  describe "#===" do
    subject(:type) { function_type }

    it "returns boolean" do
      expect(type.===(-> {})).to eql(true)
      expect(type.nil?).to eql(false)
    end

    context "in case statement" do
      let(:value) do
        case -> {}
        when type
          "accepted"
        else
          "invalid"
        end
      end

      it "returns correct value" do
        expect(value).to eql("accepted")
      end
    end
  end

  describe "#default" do
    it "returns a default value intersection type" do
      type = (t::Nominal::Nil & t::Nominal::Nil).default("foo")

      expect(type.call).to eql("foo")
    end
  end

  describe "#constructor" do
    let(:type) do
      (t::Nominal::String & t::Nominal::Nil).constructor do |input|
        input ? "#{input} world" : input
      end
    end

    it "returns the correct value" do
      expect(type.call("hello")).to eql("hello world")
      expect(type.call(nil)).to eql(nil)
      expect(type.call(10)).to eql("10 world")
    end

    it "returns if value is valid" do
      expect(type.valid?("hello")).to eql(true)
      expect(type.valid?(nil)).to eql(true)
      expect(type.valid?(10)).to eql(true)
    end
  end

  describe "#rule" do
    let(:type) { function_type }

    it "returns a rule" do
      rule = type.rule

      expect(rule.(-> {})).to be_success
      expect(rule.(nil)).to be_failure
    end
  end

  describe "#to_s" do
    context "shallow intersection" do
      let(:type) { t::Nominal::String & t::Nominal::Integer }

      it "returns string representation of the type" do
        expect(type.to_s).to eql("#<Dry::Types[Intersection<Nominal<String> & Nominal<Integer>>]>")
      end
    end

    context "constrained" do
      let(:type) { t::Nominal::String.constrained(format: /foo/) & t::Nominal::String.constrained(min_size: 4) }

      it "returns string representation of the type" do
        expect(type.to_s).to eql(
          "#<Dry::Types[Intersection<" \
          "Constrained<Nominal<String> rule=[format?(/foo/)]> & " \
          "Constrained<Nominal<String> rule=[min_size?(4)]>>]>"
        )
      end
    end

    context "intersection tree" do
      let(:type) { t::Nominal::String & t::Nominal::Integer & t::Nominal::Date & t::Nominal::Time }

      it "returns string representation of the type" do
        expect(type.to_s).to eql(
          "#<Dry::Types[Intersection<" \
          "Nominal<String> & " \
          "Nominal<Integer> & " \
          "Nominal<Date> & " \
          "Nominal<Time>" \
          ">]>"
        )
      end
    end
  end

  context "with map type" do
    let(:map_type) { t::Nominal::Hash.map(t::Nominal::Symbol, t::Nominal::String) }

    let(:schema_type) { t.Hash(foo: t::Strict::String) }

    subject(:type) { map_type & schema_type }

    it "rejects invalid input" do
      expect(type.valid?({foo: 1, bar: 1})).to be false
      expect { type[{foo: 1, bar: 1}] }.to raise_error(Dry::Types::SchemaError)
    end
  end

  describe "strict mode" do
    subject(:type) { (left & right).strict }

    let(:left) { t.Hash(foo: t::Strict::Integer) }
    let(:right) { t.Hash(bar: t::Strict::Integer) }

    it "keeps the non-strict intersection behavior unchanged" do
      loose = t::Nominal::String & t::Nominal::Integer

      expect(loose.call(312)).to eql(312)
      expect(loose.strict).not_to eql(loose)
    end

    it "merges complementary hash keys" do
      expect(type.call(foo: 1, bar: 2)).to eql(foo: 1, bar: 2)
    end

    it "can be built directly" do
      expect(left.strict_intersection(right).call(foo: 1, bar: 2)).to eql(foo: 1, bar: 2)
    end

    it "requires values on matching paths to be equal" do
      left = t.Hash(foo: t::Nominal::Integer.constructor(->(value) { value.to_i }))
      right = t.Hash(foo: t::Nominal::Integer.constructor(->(value) { value.to_i.succ }))
      mismatch = (left & right).strict

      expect {
        mismatch.call(foo: 1)
      }.to raise_error(described_class::Strict::MergeConflict) do |error|
        expect(error.stage).to eql(:merge)
        expect(error.path).to eql(%i[foo])
        expect(error.left).to eql(1)
        expect(error.right).to eql(2)
      end
    end

    it "requires array lengths to match" do
      left = t::Nominal::Array.constructor(->(_) { [1, 2] })
      right = t::Nominal::Array.constructor(->(_) { [1] })
      mismatch = (left & right).strict

      expect {
        mismatch.call(0)
      }.to raise_error(described_class::Strict::MergeConflict) do |error|
        expect(error.stage).to eql(:merge)
        expect(error.path).to eql([])
        expect(error.left).to eql([1, 2])
        expect(error.right).to eql([1])
      end
    end

    it "requires array elements to correspond by position" do
      left = t::Nominal::Array.constructor(->(_) { [1, 2] })
      right = t::Nominal::Array.constructor(->(_) { [1, 3] })
      mismatch = (left & right).strict

      expect {
        mismatch.call(0)
      }.to raise_error(described_class::Strict::MergeConflict) do |error|
        expect(error.path).to eql([1])
        expect(error.left).to eql(2)
        expect(error.right).to eql(3)
      end
    end

    it "distinguishes type validation failures from merge conflicts" do
      invalid = t.Hash(foo: t::Strict::Integer) & t.Hash(bar: t::Strict::Integer)

      expect {
        invalid.strict.call(foo: "1", bar: 2)
      }.to raise_error(described_class::Strict::TypeValidationError) do |error|
        expect(error.stage).to eql(:type_validation)
        expect(error.path).to eql([])
        expect(error.left).to eql(foo: "1")
        expect(error.right).to eql(bar: 2)
      end
    end

    it "evaluates side constructors once without replaying them for validation" do
      calls = []
      counted = ->(label) {
        ->(input) {
          calls << label
          input
        }
      }
      left = t.Hash(foo: t::Nominal::Integer.constructor(counted.call(:left)))
      right = t.Hash(bar: t::Nominal::Integer.constructor(counted.call(:right)))

      result = (left & right).strict.call(foo: 1, bar: 2)

      expect(result).to eql(foo: 1, bar: 2)
      expect(calls).to eql(%i[left right])
    end

    it "is order independent for nested conflict-free combinations" do
      first = t.Hash(foo: t::Nominal::Integer)
      second = t.Hash(bar: t::Nominal::Integer)
      third = t.Hash(baz: t::Nominal::Integer)

      left_associated = ((first & second).strict & third).strict
      right_associated = (first & (second & third).strict).strict

      input = {foo: 1, bar: 2, baz: 3}

      expect(left_associated.call(input)).to eql(input)
      expect(right_associated.call(input)).to eql(input)
    end

    it "returns a failure result from #try without raising" do
      result = type.try(foo: 1, bar: "2")

      expect(result).to be_failure
      expect(result.error).to be_a(described_class::Strict::TypeValidationError)
    end

    it "rejects combinations that cannot be checked without side effects" do
      exotic = Class.new do
        include Dry::Types::Type

        def try(input) = Dry::Types::Result::Success.new(input)
      end.new

      expect {
        (t::Nominal::Any & exotic).strict
      }.to raise_error(described_class::Strict::UnsupportedCombination)
    end

    describe "custom mergers" do
      it "uses the registered result and a side-effect free check" do
        left_marker = Module.new
        right_marker = Module.new
        left_type = Dry::Types::Nominal.new(left_marker).constructor(->(_) { left_marker })
        right_type = Dry::Types::Nominal.new(right_marker).constructor(->(_) { right_marker })

        described_class::Strict.register_merger(
          left_type,
          right_type,
          ->(_left, _right) { ::Object.new.extend(left_marker, right_marker) },
          check: ->(value) { value.is_a?(left_marker) && value.is_a?(right_marker) }
        )

        merged = (left_type & right_type).strict.call(:both)

        expect(merged).to be_a(left_marker)
        expect(merged).to be_a(right_marker)
      end

      it "still validates the merged result against pure constraints" do
        marker = Module.new
        marker_type = Dry::Types::Nominal.new(marker)

        described_class::Strict.register_merger(
          marker_type,
          t::Nominal::Integer,
          ->(_left, _right) { Object.new }
        )

        expect {
          (marker_type & t::Nominal::Integer).strict.call(1)
        }.to raise_error(described_class::Strict::TypeValidationError)
      end

      it "turns a failed custom check into a type validation error" do
        left_marker = Module.new
        right_marker = Module.new
        left_type = Dry::Types::Nominal.new(left_marker).constructor(->(_) { left_marker })
        right_type = Dry::Types::Nominal.new(right_marker).constructor(->(_) { right_marker })

        described_class::Strict.register_merger(
          left_type,
          right_type,
          ->(left, _right) { left },
          check: ->(_value) { false }
        )

        expect {
          (left_type & right_type).strict.call(:both)
        }.to raise_error(described_class::Strict::TypeValidationError) do |error|
          expect(error.stage).to eql(:custom_check)
        end
      end
    end
  end

  describe "#meta" do
    context "optional types" do
      let(:meta) { {foo: :bar} }

      subject(:type) { Dry::Types["string"].optional }

      it "uses meta from the right branch" do
        expect(type.meta(meta).meta).to eql(meta)
        expect(type.meta(meta).right.meta).to eql(meta)
      end
    end
  end
end
