# frozen_string_literal: true

RSpec.describe Dry::Types::Lattice do
  subject(:type) { described_class.of(start: 0, step: Rational(1, 2), min: 0, max: 5) }

  it "is frozen" do
    expect(type).to be_frozen
  end

  describe "validation (default mode)" do
    it "accepts exact lattice points of any numeric kind" do
      expect(type.(0)).to be(0)
      expect(type.(Rational(3, 2))).to eql(Rational(3, 2))
      expect(type.(5)).to be(5)
      expect(type.(2.5)).to be(2.5)
      expect(type.(BigDecimal("1.5"))).to eql(BigDecimal("1.5"))
    end

    it "returns the input unchanged" do
      input = Rational(3, 2)

      expect(type.(input)).to equal(input)
    end

    it "rejects off-lattice values instead of rounding them" do
      expect { type.(Rational(1, 3)) }.to raise_error(Dry::Types::ConstraintError)
      expect { type.(1.3) }.to raise_error(Dry::Types::ConstraintError)
    end

    it "rejects non-numeric input" do
      expect { type.("1.5") }.to raise_error(Dry::Types::ConstraintError)
      expect(type.valid?(nil)).to be(false)
    end

    it "enforces closed bounds by default" do
      expect(type.(0)).to be(0)
      expect(type.(5)).to be(5)
      expect { type.(Rational(11, 2)) }.to raise_error(Dry::Types::ConstraintError)
    end

    it "supports open bounds" do
      open = described_class.of(start: 0, step: 1, min: 0, max: 5,
                                min_inclusive: false, max_inclusive: false)

      expect { open.(0) }.to raise_error(Dry::Types::ConstraintError)
      expect { open.(5) }.to raise_error(Dry::Types::ConstraintError)
      expect(open.(4)).to be(4)
    end

    it "supports mixed open/closed bounds" do
      mixed = described_class.of(start: 0, step: 1, min: 0, max: 5, max_inclusive: false)

      expect(mixed.(0)).to be(0)
      expect { mixed.(5) }.to raise_error(Dry::Types::ConstraintError)
    end

    it "treats Float input by its exact binary value" do
      tenth = described_class.of(start: 0, step: Rational(1, 10))

      expect(tenth.(0.5)).to be(0.5)
      expect(tenth.valid?(0.3)).to be(false)
    end

    it "normalizes a negative step" do
      negative = described_class.of(start: 0, step: -2)

      expect(negative.definition.step).to eql(2.to_r)
      expect(negative.(4)).to be(4)
    end

    it "rejects a zero step" do
      expect { described_class.of(start: 0, step: 0) }.to raise_error(ArgumentError)
    end
  end

  describe "#nearest" do
    subject(:snapping) { described_class.of(start: 0, step: 1).nearest }

    it "snaps to the closest lattice point exactly" do
      expect(snapping.(Rational(7, 3))).to be(2)
      expect(snapping.(2.4)).to be(2)
      expect(snapping.(-2.4)).to be(-2)
    end

    it "returns exact rational points when the lattice is fractional" do
      type = described_class.of(start: Rational(1, 2), step: 1).nearest

      expect(type.(1.2)).to eql(Rational(3, 2))
      expect(type.(1.2)).to be_a(Rational)
    end

    it "breaks ties to the even lattice index by default" do
      expect(snapping.(Rational(1, 2))).to be(0)
      expect(snapping.(Rational(3, 2))).to be(2)
      expect(snapping.(Rational(5, 2))).to be(2)
      expect(snapping.(Rational(-1, 2))).to be(0)
    end

    it "supports ties: :up" do
      type = described_class.of(start: 0, step: 1).nearest(ties: :up)

      expect(type.(Rational(1, 2))).to be(1)
      expect(type.(Rational(-1, 2))).to be(0)
    end

    it "supports ties: :down" do
      type = described_class.of(start: 0, step: 1).nearest(ties: :down)

      expect(type.(Rational(1, 2))).to be(0)
      expect(type.(Rational(-1, 2))).to be(-1)
    end

    it "clamps the snapped point to the bounds" do
      type = described_class.of(start: 0, step: 1, min: 0, max: 2).nearest

      expect(type.(10)).to be(2)
      expect(type.(-10)).to be(0)
    end

    it "rejects non-numeric input" do
      expect { snapping.("2") }.to raise_error(Dry::Types::CoercionError)
      expect(snapping.valid?("2")).to be(false)
    end

    it "fails on an empty lattice" do
      empty = described_class.of(start: 0, step: 1, min: 2, max: 1).nearest

      expect { empty.(1) }.to raise_error(Dry::Types::CoercionError)
    end

    it "rejects unknown modes and tie rules" do
      expect { described_class.of(mode: :round) }.to raise_error(ArgumentError)
      expect { described_class.of(ties: :random) }.to raise_error(ArgumentError)
    end
  end

  describe "#&" do
    it "simplifies two lattices with different starts and steps" do
      by_four = described_class.of(start: 0, step: 4)
      by_six = described_class.of(start: 2, step: 6)

      combined = by_four & by_six

      expect(combined).to be_a(described_class)
      expect(combined.definition.step).to eql(12.to_r)
      expect(combined.definition.start).to eql(8.to_r)

      expect(combined.(8)).to be(8)
      expect(combined.(20)).to be(20)
      expect(combined.valid?(4)).to be(false)
      expect(combined.valid?(14)).to be(false)
    end

    it "does not collapse to the larger step" do
      combined = described_class.of(start: 0, step: 4) &
                 described_class.of(start: 2, step: 6)

      expect(combined.definition.step).not_to eql(6.to_r)
      expect(combined.definition.step).to eql(4.lcm(6).to_r)
    end

    it "simplifies rational starts and steps" do
      left = described_class.of(start: Rational(1, 2), step: Rational(3, 2))
      right = described_class.of(start: Rational(1, 4), step: Rational(5, 4))

      combined = left & right

      expect(combined.definition.start).to eql(Rational(13, 2))
      expect(combined.definition.step).to eql(Rational(15, 2))
      expect(combined.(Rational(13, 2))).to eql(Rational(13, 2))
      expect(combined.valid?(Rational(1, 2))).to be(false)
    end

    it "detects disjoint lattices as empty" do
      combined = described_class.of(start: 0, step: 2) &
                 described_class.of(start: 1, step: 2)

      expect(combined.empty?).to be(true)
      expect(combined.valid?(0)).to be(false)
      expect(combined.valid?(1)).to be(false)
      expect { combined.(0) }.to raise_error(Dry::Types::ConstraintError)
    end

    it "detects emptiness from disjoint bounds" do
      combined = described_class.of(start: 0, step: 1, max: 5) &
                 described_class.of(start: 0, step: 1, min: 6)

      expect(combined.empty?).to be(true)
    end

    it "detects bounds that exclude every lattice point" do
      combined = described_class.of(start: 0, step: 2, min: 1) &
                 described_class.of(start: 0, step: 2, max: 1)

      expect(combined.empty?).to be(true)
    end

    it "tightens bounds and combines inclusivity" do
      left = described_class.of(start: 0, step: 1, min: 0, max: 10)
      right = described_class.of(start: 0, step: 1, min: 2, max: 8, max_inclusive: false)

      combined = left & right

      expect(combined.definition.min).to eql(2.to_r)
      expect(combined.definition.max).to eql(8.to_r)
      expect(combined.definition.max_inclusive).to be(false)
      expect(combined.(2)).to be(2)
      expect { combined.(8) }.to raise_error(Dry::Types::ConstraintError)
    end

    it "makes equal bounds exclusive when either side is exclusive" do
      left = described_class.of(start: 0, step: 1, min: 3)
      right = described_class.of(start: 0, step: 1, min: 3, min_inclusive: false)

      combined = left & right

      expect(combined.definition.min_inclusive).to be(false)
      expect { combined.(3) }.to raise_error(Dry::Types::ConstraintError)
    end

    it "is commutative" do
      left = described_class.of(start: 0, step: 4)
      right = described_class.of(start: 2, step: 6)

      expect((left & right).definition).to eq((right & left).definition)
    end

    it "falls back to a generic intersection for non-lattice types" do
      combined = described_class.of(start: 0, step: 2) & Dry::Types["integer"]

      expect(combined).to be_a(Dry::Types::Intersection)
      expect(combined.(4)).to be(4)
    end
  end

  describe "#empty?" do
    it "is false for satisfiable definitions" do
      expect(type.empty?).to be(false)
    end

    it "is true when the bounds exclude every lattice point" do
      expect(described_class.of(start: 0, step: 2, min: 1, max: 1).empty?).to be(true)
      expect(described_class.of(start: 0, step: 1, min: 2, max: 1).empty?).to be(true)
    end
  end

  describe "#params" do
    subject(:params) { described_class.of(start: 0, step: Rational(1, 10)).params }

    it "parses decimal strings exactly without going through Float" do
      expect(params.("0.3")).to eql(Rational(3, 10))
      expect(params.("0.3")).to be_a(Rational)
    end

    it "parses fraction and integer strings" do
      expect(params.("3/10")).to eql(Rational(3, 10))
      expect(params.("2")).to eql(Rational(2, 1))
    end

    it "rejects strings that are off the lattice" do
      expect { params.("0.31") }.to raise_error(Dry::Types::ConstraintError)
    end

    it "rejects malformed strings" do
      expect { params.("abc") }.to raise_error(Dry::Types::CoercionError)
    end

    it "accepts exact numerics" do
      expect(params.(Rational(1, 2))).to eql(Rational(1, 2))
      expect(params.(1)).to eql(Rational(1, 1))
      expect(params.(BigDecimal("0.3"))).to eql(Rational(3, 10))
    end

    it "snaps parsed strings in nearest mode" do
      snapping = described_class.of(start: 0, step: 1).nearest.params

      expect(snapping.("2.5")).to be(2)
      expect(snapping.("2.4")).to be(2)
    end
  end

  describe "builder" do
    it "is available as Types.Lattice" do
      types = Dry.Types
      type = types.Lattice(start: 0, step: 2, min: 0)

      expect(type).to be_a(described_class)
      expect(type.(4)).to be(4)
      expect { type.(3) }.to raise_error(Dry::Types::ConstraintError)
    end
  end

  describe "#inspect" do
    it "renders the lattice definition" do
      expect(type.inspect).to eql(
        "#<Dry::Types[Lattice<start=0, step=1/2, min=0, max=5>]>"
      )
    end

    it "renders nearest mode and tie rule" do
      snapping = described_class.of(start: 0, step: 1).nearest(ties: :up)

      expect(snapping.inspect).to eql(
        "#<Dry::Types[Lattice<start=0, step=1> mode=nearest ties=up]>"
      )
    end
  end
end
