# frozen_string_literal: true

module Dry
  module Types
    # Lattice number type
    #
    # Values are exact numbers of the form `start + k * step` (k in Integer),
    # optionally restricted to an interval with open or closed ends. Start,
    # step and bounds may be Rationals; all checks are exact and no Float
    # rounding ever takes place.
    #
    # By default the type only validates its input. Snapping to the lattice
    # is opt-in via {#nearest} (or `mode: :nearest`), which returns the exact
    # nearest lattice point and breaks ties according to the `ties` rule.
    #
    # Two lattice types can be intersected with {#&}; the result is a single
    # simplified lattice type whose step is the least common multiple of both
    # steps. Emptiness of the intersection can be checked with {#empty?}.
    #
    # @example
    #   type = Dry::Types::Lattice.of(start: 0, step: Rational(1, 2), min: 0, max: 10)
    #   type.(Rational(3, 2)) # => (3/2)
    #   type.(1.3)            # raises Dry::Types::ConstraintError
    #
    #   type.nearest.(1.3)    # => (3/2)
    #
    # @api public
    class Lattice
      include Type
      include Builder
      include Options
      include Meta
      include Printable
      include ::Dry::Equalizer(:definition, :options, :meta, inspect: false, immutable: true)

      # Supported application modes
      MODES = %i[validate nearest].freeze

      # Supported tie-breaking rules for nearest-point snapping
      TIE_RULES = %i[to_even up down].freeze

      # @return [Definition] exact lattice definition
      attr_reader :definition

      # Build a lattice type from raw lattice parameters
      #
      # @param [Integer, Rational, BigDecimal, Float] start lattice origin
      # @param [Integer, Rational, BigDecimal, Float] step distance between lattice points
      # @param [Integer, Rational, BigDecimal, Float, nil] min lower bound
      # @param [Integer, Rational, BigDecimal, Float, nil] max upper bound
      # @param [Boolean] min_inclusive whether the lower bound is included
      # @param [Boolean] max_inclusive whether the upper bound is included
      # @param [Hash] options type options (:mode, :ties, :meta, ...)
      #
      # @return [Lattice]
      #
      # @api public
      def self.of(start: 0, step: 1, min: nil, max: nil, min_inclusive: true, max_inclusive: true,
                  **options)
        new(
          Definition.new(
            start: start,
            step: step,
            min: min,
            max: max,
            min_inclusive: min_inclusive,
            max_inclusive: max_inclusive
          ),
          **options
        )
      end

      # @param [Definition] definition
      # @param [Hash] options
      #
      # @api private
      def initialize(definition, **options)
        mode = options.fetch(:mode, :validate)
        ties = options.fetch(:ties, :to_even)

        unless MODES.include?(mode)
          raise ::ArgumentError, "unknown mode: #{mode.inspect}, expected one of #{MODES.inspect}"
        end

        unless TIE_RULES.include?(ties)
          raise ::ArgumentError,
                "unknown tie rule: #{ties.inspect}, expected one of #{TIE_RULES.inspect}"
        end

        super(definition, **options)
        @definition = definition
        freeze
      end

      # @return [String]
      #
      # @api public
      def name = "Lattice"

      # @return [Class]
      #
      # @api public
      def primitive = ::Numeric

      # @param [Object] value
      #
      # @return [Boolean]
      #
      # @api public
      def primitive?(value) = value.is_a?(::Numeric)

      # @return [false]
      #
      # @api public
      def default? = false

      # @return [false]
      #
      # @api public
      def constrained? = false

      # @return [false]
      #
      # @api public
      def optional? = false

      # Whether the lattice (intersected with its bounds) contains no value
      #
      # @return [Boolean]
      #
      # @api public
      def empty? = definition.empty?

      # @return [Symbol] current application mode (:validate or :nearest)
      #
      # @api public
      def mode = options.fetch(:mode, :validate)

      # @return [Symbol] tie-breaking rule used in nearest mode
      #
      # @api public
      def ties = options.fetch(:ties, :to_even)

      # @return [Boolean] whether the type snaps to the nearest lattice point
      #
      # @api public
      def nearest? = mode == :nearest

      # Opt into snapping: return a type that maps input to the exact nearest
      # lattice point instead of rejecting off-lattice values
      #
      # @param [Symbol] ties tie-breaking rule (:to_even, :up or :down)
      #
      # @return [Lattice]
      #
      # @api public
      def nearest(ties: self.ties)
        with(mode: :nearest, ties: ties)
      end

      # Params variant: coerces strings (and other numerics) to exact rational
      # values without going through Float, then applies the lattice
      #
      # @return [Constructor]
      #
      # @api public
      def params
        with(namespace: "params").constructor(Coercions::Params.method(:to_rational))
      end

      # Intersect with another type. Two lattice types are combined into a
      # single simplified lattice type (see {Definition#intersect}); the mode
      # and tie rule of the left side are kept. Any other type falls back to
      # a generic intersection.
      #
      # @param [Type] other
      #
      # @return [Lattice, Intersection]
      #
      # @api public
      def &(other)
        if other.is_a?(Lattice)
          self.class.new(definition.intersect(other.definition), **options, meta: meta)
        else
          super
        end
      end

      # @param [Object] input
      #
      # @return [Object]
      #
      # @raise [ConstraintError] when the input is not a lattice point (validate mode)
      # @raise [CoercionError] when the input cannot be snapped (nearest mode)
      #
      # @api private
      def call_unsafe(input)
        if nearest?
          point = definition.nearest(input, ties: ties)

          if point.nil?
            raise CoercionError, "#{input.inspect} cannot be snapped to #{self}"
          end

          point
        elsif definition.member?(input)
          input
        else
          raise ConstraintError.new("#{input.inspect} is not a lattice point of #{self}", input)
        end
      end

      # @param [Object] input
      #
      # @return [Object]
      #
      # @api private
      def call_safe(input, &)
        if nearest?
          point = definition.nearest(input, ties: ties)
          point.nil? ? yield : point
        elsif definition.member?(input)
          input
        else
          yield
        end
      end

      # @param [Object] input
      #
      # @yieldparam [Failure] failure
      # @yieldreturn [Result]
      #
      # @return [Result]
      #
      # @api public
      def try(input, &)
        if nearest?
          point = definition.nearest(input, ties: ties)
          return success(point) unless point.nil?

          failure = failure(input, CoercionError.new("#{input.inspect} cannot be snapped to #{self}"))
          block_given? ? yield(failure) : failure
        elsif definition.member?(input)
          success(input)
        else
          failure = failure(
            input,
            ConstraintError.new("#{input.inspect} is not a lattice point of #{self}", input)
          )
          block_given? ? yield(failure) : failure
        end
      end

      # @param (see Dry::Types::Success#initialize)
      #
      # @return [Result::Success]
      #
      # @api public
      def success(input) = Result::Success.new(input)

      # @param (see Dry::Types::Failure#initialize)
      #
      # @return [Result::Failure]
      #
      # @api public
      def failure(input, error)
        raise ::ArgumentError, "error must be a CoercionError" unless error.is_a?(CoercionError)

        Result::Failure.new(input, error)
      end
    end
  end
end
