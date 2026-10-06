# frozen_string_literal: true

module Dry
  module Types
    class Lattice
      # Value object describing an exact numeric lattice:
      #
      #   { start + k * step | k in Integer }
      #
      # optionally restricted to an interval with open or closed ends.
      # All arithmetic is exact (Rational); Floats are only ever converted
      # through their exact binary value, never rounded.
      #
      # @api public
      class Definition
        include ::Dry::Equalizer(
          :start, :step, :min, :max, :min_inclusive, :max_inclusive,
          inspect: false, immutable: true
        )

        # @return [Rational] lattice origin
        attr_reader :start

        # @return [Rational] positive distance between adjacent lattice points
        attr_reader :step

        # @return [Rational, nil] lower bound
        attr_reader :min

        # @return [Rational, nil] upper bound
        attr_reader :max

        # @return [Boolean] whether the lower bound is included
        attr_reader :min_inclusive

        # @return [Boolean] whether the upper bound is included
        attr_reader :max_inclusive

        # @param [Integer, Rational, BigDecimal, Float] start
        # @param [Integer, Rational, BigDecimal, Float] step
        # @param [Integer, Rational, BigDecimal, Float, nil] min
        # @param [Integer, Rational, BigDecimal, Float, nil] max
        # @param [Boolean] min_inclusive
        # @param [Boolean] max_inclusive
        #
        # @api private
        def initialize(start:, step:, min: nil, max: nil, min_inclusive: true, max_inclusive: true)
          @start = self.class.exact_rational(start, :start)
          @step = self.class.exact_rational(step, :step)

          raise ::ArgumentError, "step must not be zero" if @step.zero?

          @step = -@step if @step.negative?
          @min = min.nil? ? nil : self.class.exact_rational(min, :min)
          @max = max.nil? ? nil : self.class.exact_rational(max, :max)
          @min_inclusive = min_inclusive
          @max_inclusive = max_inclusive
          @empty = compute_empty
          freeze
        end

        # Whether no value can satisfy this definition
        #
        # @return [Boolean]
        #
        # @api public
        def empty? = @empty

        # Exact membership check
        #
        # @param [Object] value
        #
        # @return [Boolean]
        #
        # @api public
        def member?(value)
          return false if empty?

          point = self.class.try_exact_rational(value)
          return false if point.nil?

          index = (point - start) / step
          return false unless index.denominator == 1

          within_bounds?(point)
        end

        # Combine with another definition into a single simplified definition.
        # The lattice step of the result is the least common multiple of both
        # steps (not the larger one) and the origin is shifted to a common
        # lattice point. Returns {EMPTY} when the lattices never meet or the
        # combined bounds exclude every lattice point.
        #
        # @param [Definition] other
        #
        # @return [Definition]
        #
        # @api public
        def intersect(other)
          return EMPTY if empty? || other.empty?

          gcd = self.class.rational_gcd(step, other.step)
          offset = (other.start - start) / gcd
          return EMPTY unless offset.denominator == 1

          stride = (step / gcd).to_i
          other_stride = (other.step / gcd).to_i
          distance = offset.to_i

          index =
            if other_stride == 1
              0
            else
              (distance * self.class.mod_inverse(stride.modulo(other_stride), other_stride))
                .modulo(other_stride)
            end

          lower, lower_inclusive = tighter_lower(other)
          upper, upper_inclusive = tighter_upper(other)

          self.class.new(
            start: start + index * step,
            step: step * other_stride,
            min: lower,
            max: upper,
            min_inclusive: lower_inclusive,
            max_inclusive: upper_inclusive
          )
        end

        # Nearest lattice point to the given value, computed exactly.
        # Ties are broken according to the +ties+ rule:
        #
        # - +:to_even+ picks the point with an even lattice index
        # - +:up+ picks the larger point
        # - +:down+ picks the smaller point
        #
        # The result is clamped to the bounds (if any) and returned as an
        # Integer when it is integral, otherwise as a Rational. Returns nil
        # when the value is not numeric or the definition is empty.
        #
        # @param [Object] value
        # @param [Symbol] ties
        #
        # @return [Integer, Rational, nil]
        #
        # @api public
        def nearest(value, ties: :to_even)
          point = self.class.try_exact_rational(value)
          return nil if point.nil? || empty?

          exact = (point - start) / step
          floor_index = exact.floor
          ceil_index = exact.ceil

          index =
            if floor_index == ceil_index
              floor_index
            else
              down = exact - floor_index
              up = ceil_index - exact

              if down < up
                floor_index
              elsif up < down
                ceil_index
              else
                break_tie(floor_index, ceil_index, ties)
              end
            end

          index = clamp_index(index)
          snapped = start + index * step
          snapped.denominator == 1 ? snapped.numerator : snapped
        end

        # @return [String]
        #
        # @api private
        def to_s
          parts = ["start=#{self.class.format(start)}", "step=#{self.class.format(step)}"]
          if min
            parts << "min=#{self.class.format(min)}#{min_inclusive ? "" : " (exclusive)"}"
          end
          if max
            parts << "max=#{self.class.format(max)}#{max_inclusive ? "" : " (exclusive)"}"
          end
          parts << "empty" if empty?
          parts.join(", ")
        end

        # Range of lattice indices satisfying the bounds
        #
        # @return [Array(Integer, nil), Array(nil, nil)]
        #
        # @api private
        def index_range
          [lower_index, upper_index]
        end

        # Coerce a numeric to its exact Rational value
        #
        # @return [Rational, nil]
        #
        # @api private
        def self.try_exact_rational(value)
          case value
          when ::Rational then value
          when ::Integer then value.to_r
          when ::Float then value.to_r
          when ::BigDecimal then value.to_r
          end
        end

        # Format a rational, collapsing integral values to integers
        #
        # @return [String]
        #
        # @api private
        def self.format(value)
          value.denominator == 1 ? value.numerator.to_s : value.to_s
        end

        # @raise [ArgumentError] when the value is not numeric
        #
        # @return [Rational]
        #
        # @api private
        def self.exact_rational(value, name)
          try_exact_rational(value) ||
            raise(::ArgumentError, "#{name} must be an Integer, Rational, BigDecimal or Float, " \
                  "got #{value.inspect}")
        end

        # Greatest common divisor of two positive rationals, itself a rational
        #
        # @return [Rational]
        #
        # @api private
        def self.rational_gcd(left, right)
          Rational(
            left.numerator.gcd(right.numerator),
            left.denominator.lcm(right.denominator)
          )
        end

        # Multiplicative inverse of +a+ modulo +m+ (coprime, m > 1)
        #
        # @return [Integer]
        #
        # @api private
        def self.mod_inverse(a, m)
          old_r, r = a, m
          old_s, s = 1, 0

          until r.zero?
            quotient = old_r / r
            old_r, r = r, old_r - quotient * r
            old_s, s = s, old_s - quotient * s
          end

          old_s.modulo(m)
        end

        private

        # @api private
        def compute_empty
          lower, upper = index_range
          !lower.nil? && !upper.nil? && lower > upper
        end

        # @api private
        def lower_index
          return nil if min.nil?

          ratio = (min - start) / step
          min_inclusive ? ratio.ceil : ratio.floor + 1
        end

        # @api private
        def upper_index
          return nil if max.nil?

          ratio = (max - start) / step
          max_inclusive ? ratio.floor : ratio.ceil - 1
        end

        # @api private
        def within_bounds?(point)
          (min.nil? || (min_inclusive ? point >= min : point > min)) &&
            (max.nil? || (max_inclusive ? point <= max : point < max))
        end

        # @api private
        def clamp_index(index)
          lower, upper = index_range
          index = lower if lower && index < lower
          index = upper if upper && index > upper
          index
        end

        # @api private
        def break_tie(floor_index, ceil_index, ties)
          case ties
          when :to_even then floor_index.even? ? floor_index : ceil_index
          when :up then ceil_index
          when :down then floor_index
          else raise ::ArgumentError, "unknown tie rule: #{ties.inspect}"
          end
        end

        # @api private
        def tighter_lower(other)
          if min.nil?
            [other.min, other.min_inclusive]
          elsif other.min.nil? || min > other.min
            [min, min_inclusive]
          elsif other.min > min
            [other.min, other.min_inclusive]
          else
            [min, min_inclusive && other.min_inclusive]
          end
        end

        # @api private
        def tighter_upper(other)
          if max.nil?
            [other.max, other.max_inclusive]
          elsif other.max.nil? || max < other.max
            [max, max_inclusive]
          elsif other.max < max
            [other.max, other.max_inclusive]
          else
            [max, max_inclusive && other.max_inclusive]
          end
        end

        # Canonical empty definition (no lattice point satisfies the bounds)
        EMPTY = new(start: 0, step: 1, min: 1, max: 0).freeze
      end
    end
  end
end
