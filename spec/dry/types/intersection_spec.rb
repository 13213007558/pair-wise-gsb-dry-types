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

  describe "strict mode" do
    def schema(keys)
      t::Nominal::Hash.schema(keys)
    end

    def counted(calls, name, type, &coercion)
      type.constructor do |input|
        calls[name] += 1
        coercion.call(input)
      end
    end

    it "merges complementary hash keys and keeps equal nested values" do
      left = schema(a: t::Coercible::Integer)
      right = schema(b: t::Coercible::String)
      type = (left & right).strict

      expect(type.call(a: "1", b: 2)).to eql(a: 1, b: "2")
    end

    it "requires array lengths to match" do
      left = t.Array(t::Nominal::Any).constructor { |input| input }
      right = t.Array(t::Nominal::Any).constructor { |input| input.first(1) }
      type = (left & right).strict

      expect { type.call([1, 2]) }.to raise_error(
        Dry::Types::IntersectionConflictError
      ) { |error|
        expect(error.stage).to be(:merge)
        expect(error.path).to eql([])
        expect(error.left).to eql([1, 2])
        expect(error.right).to eql([1])
        expect(error.message).to include("array_length")
      }
    end

    it "requires array positions to correspond" do
      left = t.Array(t::Nominal::Any).constructor { |input| input }
      right = t.Array(t::Nominal::Any).constructor { |input| input.map { 2 } }
      type = (left & right).strict

      expect { type.call([1]) }.to raise_error(
        Dry::Types::IntersectionConflictError
      ) { |error|
        expect(error.path).to eql([0])
        expect(error.left).to be(1)
        expect(error.right).to be(2)
      }
    end

    it "reports nested hash conflicts with both results" do
      left = schema(a: t::Nominal::Hash.schema(b: t::Nominal::Any.constructor(&:to_i)))
      right = schema(a: t::Nominal::Hash.schema(b: t::Nominal::Any.constructor { 2 }))
      type = (left & right).strict

      failure = type.try(a: {b: 1})

      expect(failure).to be_failure
      expect(failure.error).to be_a(Dry::Types::IntersectionConflictError)
      expect(failure.error.stage).to be(:merge)
      expect(failure.error.path).to eql(%i[a b])
      expect(failure.error.left).to be(1)
      expect(failure.error.right).to be(2)
    end

    it "does not choose one side for unequal scalars" do
      default_type = t::Coercible::Integer & t::Nominal::String
      strict_type = default_type.strict

      expect(default_type.call("1")).to be(1)
      expect { strict_type.call("1") }.to raise_error(
        Dry::Types::IntersectionConflictError
      ) { |error|
        expect(error.stage).to be(:merge)
        expect(error.left).to be(1)
        expect(error.right).to eql("1")
      }
    end

    it "evaluates each side exactly once" do
      calls = Hash.new(0)
      left = schema(a: counted(calls, :a, t::Nominal::Integer, &:to_i))
      right = schema(b: counted(calls, :b, t::Nominal::String, &:to_s))
      type = (left & right).strict

      result = type.call(a: "1", b: 2)

      expect(result).to eql(a: 1, b: "2")
      expect(calls).to eql(a: 1, b: 1)

      type.valid?(a: "1", b: 2)
      expect(calls).to eql(a: 2, b: 2)
    end

    it "still evaluates the other side once when one side fails" do
      calls = Hash.new(0)
      left = counted(calls, :left, t::Strict::Integer) { _1 }
      right = counted(calls, :right, t::Strict::Integer) { _1 }
      type = (left & right).strict

      result = type.try("1")

      expect(result).to be_failure
      expect(result.error).to be_a(Dry::Types::IntersectionValidationError)
      expect(result.error.stage).to be(:validation)
      expect(calls).to eql(left: 1, right: 1)
    end

    it "distinguishes merged values that fail a side constraint" do
      calls = Hash.new(0)
      left = schema(name: counted(calls, :name, t::Strict::String, &:to_s))
      right = schema(active: t::Strict::Bool)
      registry = Dry::Types::Intersection::MergeRegistry.new.register(
        [left.pristine, right.pristine],
        ->(left_result, right_result) {
          left_result.merge(right_result).merge(name: 1)
        }
      )
      type = (left & right).strict(registry: registry)

      result = type.try(name: :ada, active: true)

      expect(result).to be_failure
      expect(result.error).to be_a(Dry::Types::IntersectionValidationError)
      expect(result.error.stage).to be(:validation)
      expect(result.error.path).to eql([:name])
      expect(result.error.left).to eql(name: "ada")
      expect(result.error.right).to eql(active: true)
      expect(calls).to eql(name: 1)
    end

    it "supports registered mergers and side-effect-free result checkers" do
      left = schema(first: t::Strict::String)
      right = schema(last: t::Strict::String)
      merger = ->(left_result, right_result) {
        left_result.merge(right_result).merge(
          full_name: "#{left_result.fetch(:first)} #{right_result.fetch(:last)}"
        )
      }
      checker = ->(result) { result.fetch(:full_name).include?(" ") }
      registry = Dry::Types::Intersection::MergeRegistry
        .new
        .register([left.pristine, right.pristine], merger, checker)
      type = (left & right).strict(registry: registry)

      expect(type.call(first: "Ada", last: "Lovelace")).to eql(
        first: "Ada", last: "Lovelace", full_name: "Ada Lovelace"
      )
    end

    it "supports the process-wide merger registry" do
      left = t::Nominal::Hash.schema(first: t::Strict::String)
      right = t::Nominal::Hash.schema(last: t::Strict::String)
      registry_class = Dry::Types::Intersection::MergeRegistry
      pair = [left.pristine, right.pristine]

      registry_class.register(pair) do |left_result, right_result|
        left_result.merge(right_result).merge(full_name: "global merger")
      end

      type = (left & right).strict

      expect(type.call(first: "Ada", last: "Lovelace")).to include(
        full_name: "global merger"
      )
    ensure
      registry_class.unregister(pair)
    end

    it "uses a custom merger across nested strict intersections" do
      left = t::Nominal::Hash.schema(first: t::Strict::String)
      middle = t::Nominal::Hash.schema(last: t::Strict::String)
      right = t::Nominal::Hash.schema(active: t::Strict::Bool)
      registry = Dry::Types::Intersection::MergeRegistry
        .new
        .register([(left & middle).strict, right]) do |left_result, right_result|
          left_result.merge(right_result).merge(nested_custom: true)
        end
      type = ((left & middle).strict & right).strict(registry: registry)

      expect(type.call(first: "Ada", last: "Lovelace", active: true)).to include(
        nested_custom: true
      )
    end

    it "reports a failed custom checker as a merge conflict" do
      left = schema(first: t::Strict::String)
      right = schema(last: t::Strict::String)
      registry = Dry::Types::Intersection::MergeRegistry
        .new
        .register(
          [left.pristine, right.pristine],
          ->(left_result, right_result) { left_result.merge(right_result) },
          ->(_result) { false }
        )
      type = (left & right).strict(registry: registry)

      expect { type.call(first: "Ada", last: "Lovelace") }.to raise_error(
        Dry::Types::IntersectionConflictError
      ) { |error|
        expect(error.stage).to be(:merge)
        expect(error.message).to include("custom_checker")
      }
    end

    it "rejects types whose pure constraints cannot be recovered" do
      type = t::Strict::Integer.constructor(&:to_i).lax & t::Strict::String

      expect { type.strict }.to raise_error(
        Dry::Types::IntersectionUnverifiableError, /lax types/
      )
    end

    it "is associative for nested intersections without custom mergers" do
      calls = Hash.new(0)
      first = schema(a: counted(calls, :a, t::Nominal::Integer, &:to_i))
      second = schema(b: counted(calls, :b, t::Nominal::String, &:to_s))
      third = schema(c: counted(calls, :c, t::Nominal::String, &:to_s))

      left_associated = ((first & second).strict & third).strict
      right_associated = (first & (second & third).strict).strict
      input = {a: "1", b: 2, c: true}

      expect(left_associated.call(input)).to eql(a: 1, b: "2", c: "true")
      expect(calls).to eql(a: 1, b: 1, c: 1)
      expect(right_associated.call(input)).to eql(a: 1, b: "2", c: "true")
      expect(calls).to eql(a: 2, b: 2, c: 2)
    end

    it "preserves the non-strict default behavior" do
      type = t.Array(t::Nominal::Any) & t.Array(t::Nominal::Any)

      expect(type.call([1, 2])).to eql([1, 2])
      expect(type.strict).not_to equal(type)
    end

    it "hides the merger registry in its string representation" do
      type = (t::Nominal::String & t::Nominal::Integer).strict

      expect(type.to_s).to eql(
        "#<Dry::Types[Intersection<Nominal<String> & Nominal<Integer> " \
        "options={strict: true}>]>"
      )
    end
  end
end
