# frozen_string_literal: true

module Dry
  module Types
    # Common API for building type objects in a convenient way
    #
    #
    # @api public
    module BuilderMethods
      # @api private
      def included(base)
        super
        base.extend(BuilderMethods)
      end

      # Build an array type.
      #
      # Shortcut for Array#of.
      #
      # @example
      #   Types::Strings = Types.Array(Types::String)
      #
      # @param [Dry::Types::Type] type
      #
      # @return [Dry::Types::Array]
      def Array(type) = Strict(::Array).of(type)

      # Build a hash schema
      #
      # @param [Hash{Symbol => Dry::Types::Type}] type_map
      #
      # @return [Dry::Types::Array]
      def Hash(type_map) = Strict(::Hash).schema(type_map)

      # Build a type which values are instances of a given class
      # Values are checked using `is_a?` call
      #
      # @example
      #   Types::Error = Types.Instance(StandardError)
      #   Types::Error = Types.Strict(StandardError)
      #   Types.Strict(Integer) == Types::Strict::Int # => true
      #
      # @param [Class,Module] klass Class or module
      #
      # @return [Dry::Types::Type]
      def Instance(klass)
        unless klass.is_a?(::Module)
          raise ::ArgumentError, "Expected a class or module, got #{klass.inspect}"
        end

        Nominal(klass).constrained(type: klass)
      end

      alias_method :Strict, :Instance

      # Build a type with a single value
      # The equality check done with `eql?`
      #
      # @param [Object] value
      #
      # @return [Dry::Types::Type]
      def Value(value) = Nominal(value.class).constrained(eql: value)

      # Build a type with a single value
      # The equality check done with `equal?`
      #
      # @param [Object] object
      #
      # @return [Dry::Types::Type]
      def Constant(object) = Nominal(object.class).constrained(is: object)

      # Build a constructor type
      # If no constructor block given it uses .new method
      #
      # @param [Class] klass
      # @param [#call,nil] cons Value constructor
      # @param [#call,nil] block Value constructor
      #
      # @return [Dry::Types::Type]
      def Constructor(klass, cons = nil, &block) # rubocop:disable Metrics/PerceivedComplexity
        if klass.is_a?(Type)
          if cons || block
            klass.constructor(cons || block)
          else
            klass
          end
        else
          Nominal(klass).constructor(cons || block || klass.method(:new))
        end
      end

      # Build a nominal type
      #
      # @param [Class] klass
      #
      # @return [Dry::Types::Type]
      def Nominal(klass)
        if klass <= ::Array
          Array.new(klass)
        elsif klass <= ::Hash
          Hash.new(klass)
        else
          Nominal.new(klass)
        end
      end

      # Build a map type
      #
      # @example
      #   Types::IntMap = Types.Map(Types::Strict::Integer, 'any')
      #   Types::IntStringMap = Types.Map(Types::Strict::Integer, Types::Strict::String)
      #
      # @param [Type] key_type Key type
      # @param [Type] value_type Value type
      #
      # @return [Dry::Types::Map]
      def Map(key_type, value_type)
        Nominal(::Hash).map(key_type, value_type)
      end

      # Builds a constrained nominal type accepting any value that
      # responds to given methods
      #
      # @example
      #   Types::Callable = Types.Interface(:call)
      #   Types::Contact = Types.Interface(:name, :address)
      #
      # @param methods [Array<String, Symbol>] Method names
      #
      # @return [Dry::Types::Contrained]
      def Interface(*methods)
        methods.reduce(Types["nominal.any"]) do |type, method|
          type.constrained(respond_to: method)
        end
      end

      # Build a lattice number type: exact values of the form
      # `start + k * step` (k in Integer), optionally bounded by an
      # open/closed interval. The type only validates by default; use
      # `.nearest` to opt into exact snapping.
      #
      # @example
      #   Types.Lattice(start: 0, step: Rational(1, 2), min: 0, max: 10)
      #
      # @param [Integer, Rational, BigDecimal, Float] start lattice origin
      # @param [Integer, Rational, BigDecimal, Float] step distance between lattice points
      # @param [Integer, Rational, BigDecimal, Float, nil] min lower bound
      # @param [Integer, Rational, BigDecimal, Float, nil] max upper bound
      # @param [Boolean] min_inclusive whether the lower bound is included
      # @param [Boolean] max_inclusive whether the upper bound is included
      # @param [Hash] options type options (:mode, :ties, :meta, ...)
      #
      # @return [Dry::Types::Lattice]
      def Lattice(start: 0, step: 1, min: nil, max: nil, min_inclusive: true, max_inclusive: true,
                  **options)
        Dry::Types::Lattice.of(
          start: start,
          step: step,
          min: min,
          max: max,
          min_inclusive: min_inclusive,
          max_inclusive: max_inclusive,
          **options
        )
      end
    end
  end
end
