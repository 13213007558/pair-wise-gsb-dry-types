# frozen_string_literal: true

module Dry
  module Types
    # Numbers belonging to a lattice +origin + k * step+ intersect an interval.
    #
    # Both origin and step are stored as Rational numbers, so validation and
    # rounding never lose precision through Float.
    #
    # @api public
    class LatticeNumber
      include Type
      include Options
      include Meta
      include Builder
      include Printable
      include ::Dry::Equalizer(
        :origin, :step, :lower_bound, :upper_bound,
        :exclude_begin, :exclude_end, :rounding, :tie,
        :options, :meta,
        inspect: false,
        immutable: true
      )

      # Tie-breaking strategies used by the +nearest+ rounding mode
      TIES = %i[up down even].freeze

      # @return [Rational] origin of the lattice, always a member
      attr_reader :origin

      # @return [Rational] distance between neighbouring lattice points
      attr_reader :step

      # @return [Rational] inclusive or exclusive lower bound
      attr_reader :lower_bound

      # @return [Rational] inclusive or exclusive upper bound
      attr_reader :upper_bound

      # @return [Boolean] whether the lower endpoint is excluded
      attr_reader :exclude_begin

      # @return [Boolean] whether the upper endpoint is excluded
      attr_reader :exclude_end

      # @return [Symbol, nil] +:nearest+ when the type rounds to a point
      attr_reader :rounding

      # @return [Symbol] tie-breaking rule, one of {TIES}
      attr_reader :tie

      # @param [Numeric, String] origin a lattice member
      # @param [Numeric, String] step positive lattice spacing
      # @param [Range, nil] range open/closed interval restriction; Ruby ranges
      #   are closed at the beginning, use +exclude_begin:+ for open starts
      # @param [Boolean] exclude_begin whether the lower endpoint is excluded
      # @param [Symbol, nil] rounding pass +:nearest+ to round to a point
      # @param [Symbol] tie one of {TIES}, applied on exact ties
      #
      # @api public
      def initialize(origin = 0, step = 1, meta: EMPTY_HASH, **options) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/ParameterLists
        origin = options.fetch(:origin, origin)
        step = options.fetch(:step, step)
        range = options.fetch(:range, nil)
        @exclude_begin = options.fetch(:exclude_begin, false)
        @rounding = options.fetch(:rounding, nil)
        @tie = options.fetch(:tie, :up)
        options = options.except(:origin, :step, :range, :exclude_begin, :rounding, :tie)
        super(meta: meta, **options)

        @origin = Coercions.to_rational(origin)
        @step = Coercions.to_rational(step)

        raise ::ArgumentError, "step must be positive, #{step.inspect} given" unless @step.positive?
        unless TIES.include?(@tie)
          raise ::ArgumentError, "tie must be one of #{TIES.map(&:inspect).join(", ")}"
        end
        if @rounding && @rounding != :nearest
          raise ::ArgumentError, "rounding must be :nearest, #{@rounding.inspect} given"
        end

        apply_range(range)

        freeze
      end

      # @return [String]
      #
      # @api public
      def name = primitive.name

      # Validated values are Rational numbers
      #
      # @return [Class]
      #
      # @api public
      def primitive = ::Rational

      # @return [false]
      def default? = false

      # @return [false]
      def constrained? = false

      # @return [false]
      def optional? = false

      # @return [Range, nil] interval representation of the bounds
      #
      # @api public
      def range
        return nil if lower_bound.nil?

        ::Range.new(lower_bound, upper_bound, exclude_end || upper_bound.nil?)
      end

      # Whether the lattice has no point inside its interval
      #
      # @return [Boolean]
      #
      # @api public
      def empty?
        minimum_point.nil?
      end

      # @param [Object] value
      #
      # @return [Boolean]
      #
      # @api private
      def primitive?(value)
        value.is_a?(::Integer) || value.is_a?(::Rational)
      end

      # @param [Object] input
      #
      # @return [Rational]
      #
      # @raise [CoercionError, ConstraintError]
      #
      # @api private
      def call_unsafe(input)
        value = Coercions.to_rational(input)
        point = rounding ? nearest_point(value) : value

        unless member?(point)
          raise ConstraintError.new(
            "#{input.inspect} is not a member of #{inspect}",
            input
          )
        end

        point
      end

      # @param [Object] input
      #
      # @return [Object]
      #
      # @api private
      def call_safe(input, &block)
        result = try(input)
        return result.input if result.success?

        block_given? ? yield(result) : input
      end

      # @param [Object] input
      #
      # @return [Result]
      #
      # @api public
      def try(input, &)
        value = Coercions.to_rational(input)
      rescue CoercionError => error
        failure = failure(input, error)
        block_given? ? yield(failure) : failure
      else
        point = rounding ? nearest_point(value) : value
        if member?(point)
          success(point)
        else
          failure = failure(
            input,
            ConstraintError.new(
              "#{input.inspect} is not a member of #{inspect}",
              input
            )
          )
          block_given? ? yield(failure) : failure
        end
      end

      # @see Nominal#to_ast
      #
      # @return [Array]
      #
      # @api public
      def to_ast(meta: true)
        [
          :lattice_number,
          [
            origin, step, range, exclude_begin, rounding, tie,
            meta ? self.meta : EMPTY_HASH
          ]
        ]
      end

      # @return [LatticeNumber]
      def lax = self

      # @return [Proc]
      def to_proc = proc { |value| self.(value) }

      # Rebuild the lattice while preserving its current state
      #
      # @api private
      def with(**new_options)
        return self if new_options.empty?

        current = {
          range: range,
          exclude_begin: exclude_begin,
          rounding: rounding,
          tie: tie,
          **options,
          meta: @meta
        }

        self.class.new(origin, step, **current.merge(new_options))
      end

      # @api private
      def success(input) = Result::Success.new(input)

      # @api private
      def failure(input, error) = Result::Failure.new(input, error)

      # Return the same lattice restricted by an additional interval.
      #
      # @param [Range] interval
      # @param [Boolean] exclude_begin
      #
      # @return [LatticeNumber]
      #
      # @api public
      def constrain_range(interval, exclude_begin: false)
        with(origin: origin, step: step, **merged_bounds(interval, exclude_begin))
      end

      # Intersect with another lattice. The result is simplified to a single
      # lattice when the intersection is non-empty, otherwise an empty type.
      #
      # @param [LatticeNumber] other
      #
      # @return [LatticeNumber, Empty]
      #
      # @api public
      def intersect(other)
        return other.canonical if eql?(other)

        period = rational_lcm(step, other.step)
        u = (period / step).to_i
        v = (period / other.step).to_i

        gcd = u.gcd(v)
        shared_origin = first_common_point(other, period, u, v, gcd)

        return shared_origin if shared_origin.is_a?(Empty)
        shared_origin = shared_origin % period
        options = merged_interval(other)

        return Empty.new(self, other) if options.nil?

        aligned = align_options(shared_origin, period, options)
        return Empty.new(self, other) if aligned.nil?

        result = LatticeNumber.new(
          shared_origin,
          period,
          tie: combine_tie(other),
          rounding: rounding || other.rounding,
          **aligned
        )
        canonical = result.canonical
        canonical.empty? ? Empty.new(self, other) : canonical
      end

      # Align the interval's lower endpoint to the first lattice point inside
      # it. This preserves the member set while making the representation
      # independent of the intersection order.
      #
      # @api private
      def align_options(shared_origin, period, options)
        range = options[:range]
        return options if range.nil?

        lower = Coercions.to_rational(range.begin)
        upper = range.end.nil? ? nil : Coercions.to_rational(range.end)
        index = ((lower - shared_origin) / period).ceil
        index += 1 if options[:exclude_begin] && shared_origin + index * period == lower
        first_point = shared_origin + index * period

        return if upper && first_point > upper
        return if upper && first_point == upper && range.exclude_end?

        options.merge(
          range: ::Range.new(first_point, upper, upper.nil? ? false : range.exclude_end?),
          exclude_begin: false
        )
      end

      # @api private
      def combine_tie(other)
        if rounding == :nearest && other.rounding == :nearest && tie != other.tie
          raise ::ArgumentError,
            "cannot intersect nearest lattices with different tie rules: " \
            "#{tie.inspect} vs #{other.tie.inspect}"
        end

        rounding == :nearest ? tie : other.tie
      end

      # Equivalent lattice whose origin is the smallest member in its interval,
      # or the smallest non-negative member when the lattice is unbounded.
      #
      # @return [LatticeNumber]
      #
      # @api private
      def canonical
        if lower_bound.nil?
          return with(origin: origin % step)
        end

        floor_index = ((lower_bound - origin) / step).floor
        candidate = origin + floor_index * step
        candidate += step if candidate < lower_bound ||
          (exclude_begin && candidate == lower_bound)
        with(origin: candidate)
      end

      # Smallest lattice point contained in the interval
      #
      # @return [Rational, nil]
      #
      # @api private
      def minimum_point
        return origin if lower_bound.nil?

        index = ((lower_bound - origin) / step).ceil
        index += 1 if exclude_begin && origin + index * step == lower_bound
        point = origin + index * step

        in_interval?(point) ? point : nil
      end

      private

      # @api private
      def member?(point)
        on_lattice?(point) && in_interval?(point)
      end

      # @api private
      def on_lattice?(point)
        ((point - origin) / step).denominator == 1
      end

      # @api private
      def in_interval?(point)
        return true if lower_bound.nil?

        lower_ok = exclude_begin ? point > lower_bound : point >= lower_bound
        upper_ok =
          if upper_bound.nil?
            true
          elsif exclude_end
            point < upper_bound
          else
            point <= upper_bound
          end
        lower_ok && upper_ok
      end

      # Round an exact Rational value to the nearest lattice point
      #
      # @param [Rational] value
      #
      # @return [Rational]
      #
      # @api private
      def nearest_point(value)
        position = (value - origin) / step
        index = position.floor
        lower = origin + index * step
        fraction = position - index

        return lower if fraction < 1r / 2
        return origin + (index + 1) * step if fraction > 1r / 2

        tie_point(lower, origin + (index + 1) * step, index)
      end

      # @api private
      def tie_point(lower, upper, index)
        case tie
        when :down then lower
        when :even then index.even? ? lower : upper
        else upper
        end
      end

      # @api private
      def apply_range(range)
        if range.nil?
          @lower_bound = nil
          @upper_bound = nil
          @exclude_end = false
        else
          raise ::ArgumentError, "range must be a Range, #{range.class} given" unless range.is_a?(::Range)

          @lower_bound = Coercions.to_rational(range.begin)
          @upper_bound = range.end.nil? ? nil : Coercions.to_rational(range.end)
          @exclude_end = range.exclude_end?
          raise ::ArgumentError, "range must be ascending" if upper_bound && lower_bound > upper_bound
        end
      end

      # @api private
      def bounds_for(range, open_lower = false)
        return {range: nil, exclude_begin: false} if range.nil?

        {range: range, exclude_begin: open_lower}
      end

      # @api private
      def merged_bounds(interval, open_lower)
        return bounds_for(interval, open_lower) if lower_bound.nil?

        lower = [lower_bound, Coercions.to_rational(interval.begin)].max
        upper = [upper_bound, interval.end && Coercions.to_rational(interval.end)].compact.min
        lower_open =
          (exclude_begin && lower == lower_bound) ||
          (open_lower && lower == Coercions.to_rational(interval.begin))
        upper_open =
          upper_bound.nil? ? interval.exclude_end? : exclude_end || interval.exclude_end?

        bounds_for(::Range.new(lower, upper, upper_open), lower_open)
      end

      # @api private
      def merged_interval(other)
        return bounds_for(other.range, other.exclude_begin) if lower_bound.nil?
        return bounds_for(range, exclude_begin) if other.lower_bound.nil?

        lower = [lower_bound, other.lower_bound].max
        upper = [upper_bound, other.upper_bound].compact.min
        return if upper && lower > upper
        open_lower =
          (exclude_begin && lower == lower_bound) ||
          (other.exclude_begin && lower == other.lower_bound)
        bounded = !upper_bound.nil? && !other.upper_bound.nil?
        open_upper = bounded && (exclude_end || other.exclude_end)

        return if bounded && lower == upper && (open_lower || open_upper)

        merged = ::Range.new(lower, upper, open_upper)
        bounds_for(merged, open_lower)
      end

      # LCM of two positive Rational numbers
      #
      # @api private
      def rational_lcm(left, right)
        left.numerator.lcm(right.numerator).quo(
          left.denominator.gcd(right.denominator)
        )
      end

      # Solve origin + k*step == other.origin + j*other.step.
      #
      # With +period = u*step = v*other.step+, multiplying the equality by
      # +u*v/period+ turns it into the integer equation
      # +k*v - j*u = delta*u*v/period+, solved as a congruence modulo +u+.
      #
      # @api private
      def first_common_point(other, period, u, v, gcd) # rubocop:disable Metrics/AbcSize
        rhs = (other.origin - origin) * u * v / period

        return Empty.new(self, other) unless rhs.denominator == 1

        modulus = u / gcd
        factor = v / gcd

        index =
          if modulus == 1
            0
          else
            (rhs.numerator * modular_inverse(factor, modulus)) % modulus
          end

        origin + index * step
      end

      # @api private
      def modular_inverse(number, modulus)
        _gcd, inverse, = extended_gcd(number % modulus, modulus)
        inverse % modulus
      end

      # @api private
      def extended_gcd(left, right)
        return [right, 0, 1] if left.zero?

        gcd, x, y = extended_gcd(right % left, left)
        [gcd, y - (right / left) * x, x]
      end
    end
  end
end

require "dry/types/lattice_number/empty"
