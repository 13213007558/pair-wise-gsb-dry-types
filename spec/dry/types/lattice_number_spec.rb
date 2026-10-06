# frozen_string_literal: true

RSpec.describe Dry::Types::LatticeNumber do
  subject(:type) { Dry::Types::LatticeNumber.new(1r/3, 1r/2) }

  it_behaves_like "Dry::Types::Nominal without primitive"
  it_behaves_like "Dry::Types::Nominal#meta"
  it_behaves_like "a composable constructor"

  describe "construction" do
    it "keeps origin and step as exact Rational values" do
      lattice = described_class.new("1/7", "0.25")

      expect(lattice.origin).to eql(1r/7)
      expect(lattice.step).to eql(1r/4)
    end

    it "rejects a non-positive step" do
      expect { described_class.new(0, 0) }.to raise_error(ArgumentError, /positive/)
      expect { described_class.new(0, -1) }.to raise_error(ArgumentError, /positive/)
    end

    it "rejects an unknown tie rule" do
      expect {
        described_class.new(0, 1, rounding: :nearest, tie: :sideways)
      }.to raise_error(ArgumentError, /tie/)
    end

    it "rejects an unknown rounding mode" do
      expect {
        described_class.new(0, 1, rounding: :floor)
      }.to raise_error(ArgumentError, /nearest/)
    end

    it "is frozen" do
      expect(type).to be_frozen
    end
  end

  describe "validation (the default mode)" do
    it "accepts exact lattice points" do
      expect(type.(1r/3)).to eql(1r/3)
      expect(type.("1/3")).to eql(1r/3)
      expect(type.(-2r/3)).to eql(-2r/3)
    end

    it "does not silently round nearby values" do
      expect(type.valid?(1r/3 + 1r/100)).to be(false)
      expect { type[1r/3 + 1r/100] }.to raise_error(Dry::Types::ConstraintError)
    end

    it "returns the original input from the safe call on failure" do
      expect(type.(1r/3 + 1r/100) { :fallback }).to be(:fallback)
    end

    it "wraps outcomes in Result objects via #try" do
      expect(type.try(1r/3)).to be_success
      expect(type.try(0)).to be_failure
    end

    it "reports failure for non-numeric strings without rounding" do
      expect(type.try("x")).to be_failure
    end

    it "matches values through ===" do
      expect(type === 1r/3).to be(true)
      expect(type === 0).to be(false)
    end
  end

  describe "intervals" do
    it "honours a closed interval" do
      lattice = described_class.new(0, 1, range: 1..3)

      expect(lattice.valid?(0)).to be(false)
      expect(lattice.valid?(1)).to be(true)
      expect(lattice.valid?(3)).to be(true)
      expect(lattice.valid?(4)).to be(false)
    end

    it "honours an open upper endpoint" do
      lattice = described_class.new(0, 1, range: 1...3)

      expect(lattice.valid?(3)).to be(false)
      expect(lattice.valid?(2)).to be(true)
    end

    it "honours an open lower endpoint" do
      lattice = described_class.new(0, 1, range: 1..3, exclude_begin: true)

      expect(lattice.valid?(1)).to be(false)
      expect(lattice.valid?(2)).to be(true)
      expect(lattice.minimum_point).to eq(2)
    end

    it "detects a lattice with no point inside its interval" do
      lattice = described_class.new(0, 5, range: 1...5)

      expect(lattice).to be_empty
      expect(lattice.minimum_point).to be_nil
    end

    it "adds a further interval via #constrain_range" do
      lattice = described_class.new(0, 1).constrain_range(0..2).constrain_range(1..3)

      expect(lattice.range).to eq(1..2)
      expect(lattice.valid?(0)).to be(false)
      expect(lattice.valid?(2)).to be(true)
    end
  end

  describe "nearest rounding" do
    subject(:nearest) { described_class.new(0, 2, rounding: :nearest) }

    it "returns an exact Rational lattice point" do
      expect(nearest.("1.1")).to eql(2r)
      expect(nearest.("0.9")).to eql(0r)
      expect(nearest.(1r/2)).to be_a(Rational)
    end

    it "rounds ties upwards by default" do
      expect(nearest.(1)).to eq(2)
    end

    it "rounds ties down with tie: :down" do
      down = described_class.new(0, 2, rounding: :nearest, tie: :down)
      expect(down.(1)).to eq(0)
    end

    it "rounds ties towards an even index with tie: :even" do
      even = described_class.new(0, 2, rounding: :nearest, tie: :even)
      expect(even.(1)).to eq(0)
      expect(even.(3)).to eq(4)
    end

    it "uses the exact value even when a Float is supplied" do
      lattice = described_class.new(1r/3, 1r/2, rounding: :nearest)
      expect(lattice.(0.9)).to eql(5r/6)
    end

    it "still respects the interval after rounding" do
      bounded = described_class.new(0, 2, range: 2.., rounding: :nearest)
      expect { bounded[0] }.to raise_error(Dry::Types::ConstraintError)
      expect(bounded.(2)).to eq(2)
    end
  end

  describe "intersection simplification" do
    it "simplifies two lattices with different origins and steps" do
      left = described_class.new(1r/2, 2)
      right = described_class.new(5r/2, 3)

      common = left & right

      expect(common).to be_a(described_class)
      expect(common.origin).to eq(5r/2)
      expect(common.step).to eq(6)
      expect(common.valid?(5r/2)).to be(true)
      expect(common.valid?(17r/2)).to be(true)
      expect(common.valid?(1r/2)).to be(false)
    end

    it "does not simply take the largest step" do
      left = described_class.new(0, 6)
      right = described_class.new(0, 4)

      common = left & right

      expect(common.step).to eq(12)
      expect(common.step).not_to eql(6)
    end

    it "works with Rational steps whose intersection is non-trivial" do
      left = described_class.new(1r/3, 1r/2)
      right = described_class.new(1r/3, 1r/3)

      common = left & right

      expect(common.step).to eq(1)
      expect(common.valid?(1r/3)).to be(true)
      expect(common.valid?(4r/3)).to be(true)
      expect(common.valid?(5r/6)).to be(false)
    end

    it "returns an empty type for incompatible lattices" do
      left = described_class.new(1r/3, 1r/2)
      right = described_class.new(2r/5, 1r/3)

      common = left & right

      expect(common).to be_a(described_class::Empty)
      expect(common).to be_empty
      expect(common.valid?(0)).to be(false)
      expect(common.try(0)).to be_failure
      expect { common[0] }.to raise_error(Dry::Types::ConstraintError)
    end

    it "returns an empty type when the intervals do not overlap" do
      left = described_class.new(0, 2, range: 0..3)
      right = described_class.new(0, 2, range: 5..8)

      expect(left & right).to be_a(described_class::Empty)
    end

    it "returns an empty type when no common point lies in both intervals" do
      left = described_class.new(0, 2, range: 0...2)
      right = described_class.new(0, 2, range: 2..4)

      expect(left & right).to be_a(described_class::Empty)
    end

    it "intersects intervals as well as lattices" do
      left = described_class.new(0, 2, range: 0..10)
      right = described_class.new(0, 3, range: 4..20)

      common = left & right

      expect(common.range).to eq(6..10)
      expect(common.valid?(6)).to be(true)
      expect(common.valid?(0)).to be(false)
    end

    it "stays empty when intersected again" do
      empty = described_class.new(1r/3, 1r/2) & described_class.new(2r/5, 1r/3)

      expect(empty & type).to be_a(described_class::Empty)
    end

    it "stays empty when constrained to another interval" do
      empty = described_class.new(1r/3, 1r/2) & described_class.new(2r/5, 1r/3)

      expect(empty.constrain_range(0..100)).to be_a(described_class::Empty)
    end

    it "produces an equal result for both orders" do
      left = described_class.new(1r/2, 2)
      right = described_class.new(5r/2, 3)

      expect(left & right).to eql(right & left)
    end

    it "leaves non-lattice intersections as compositions" do
      integer = Dry::Types["strict.integer"]
      expect(type & integer).to be_a(Dry::Types::Intersection)
    end

    it "propagates nearest rounding through the intersection" do
      left = described_class.new(0, 2, rounding: :nearest)
      right = described_class.new(0, 3, rounding: :nearest)

      common = left & right

      expect(common.rounding).to be(:nearest)
      expect(common.("5")).to eq(6)
    end

    it "refuses to combine nearest lattices with conflicting tie rules" do
      left = described_class.new(0, 2, rounding: :nearest, tie: :up)
      right = described_class.new(0, 3, rounding: :nearest, tie: :down)

      expect { left & right }.to raise_error(ArgumentError, /tie/)
    end
  end

  describe "registered types and builder" do
    it "is registered under lattice_number identifiers" do
      expect(Dry::Types["lattice_number"]).to be_a(described_class)
      expect(Dry::Types["strict.lattice_number"]).to be_a(described_class)
    end

    it "is built with Types.Lattice" do
      lattice = Dry.Types.Lattice("0", "1/2")
      expect(lattice).to be_a(described_class)
      expect(lattice.step).to eql(1r/2)
    end
  end

  describe "printing" do
    it "renders a readable representation" do
      expect(type.inspect).to include("Lattice")
      expect(type.inspect).to include("1/3")
    end
  end

  describe "AST" do
    it "exposes its definition" do
      expect(type.to_ast.first).to be(:lattice_number)
      expect((type & type).to_ast.first).to be(:lattice_number)
    end
  end
end
