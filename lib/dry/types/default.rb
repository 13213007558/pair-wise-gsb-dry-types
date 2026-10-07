# frozen_string_literal: true

module Dry
  module Types
    # Default types are useful when a missing value should be replaced by a default one
    #
    # @api public
    class Default
      # @api private
      class Callable < Default
        include ::Dry::Equalizer(:type, inspect: false, immutable: true)

        # Evaluates given callable
        # @return [Object]
        def evaluate
          value.call(type)
        end

        # @return [true]
        def callable?
          true
        end
      end

      include Type
      include Decorator
      include Builder
      include Printable
      include ::Dry::Equalizer(:type, :value, inspect: false, immutable: true)

      # @return [Object]
      attr_reader :value

      alias_method :evaluate, :value

      # @param [Object, #call] value
      #
      # @return [Class] {Default} or {Default::Callable}
      #
      # @api private
      def self.[](value)
        if value.respond_to?(:call)
          Callable
        else
          self
        end
      end

      # @param [Type] type
      # @param [Object] value
      #
      # @api private
      def initialize(type, value, **)
        super
        @value = value
      end

      # Build a constrained type
      #
      # @param [Array] args see {Dry::Types::Builder#constrained}
      #
      # @return [Default]
      #
      # @api public
      def constrained(...) = type.constrained(...).default(value)

      # @return [true]
      #
      # @api public
      def default? = true

      # @return [Boolean]
      #
      # @api public
      def codec? = type.codec?

      # @return [Boolean]
      #
      # @api public
      def decoder? = type.decoder?

      # @return [Boolean]
      #
      # @api public
      def encoder? = type.encoder?

      # @param [Object] input
      #
      # @return [Result::Success]
      #
      # @api public
      def try(input = Undefined, &)
        if input.equal?(Undefined)
          success(evaluate)
        else
          type.try(input)
        end
      end

      # @return [Boolean]
      #
      # @api public
      def valid?(value = Undefined) = Undefined.equal?(value) || super

      # @param [Object] input
      #
      # @return [Object] value passed through {#type} or {#default} value
      #
      # @api private
      def call_unsafe(input = Undefined)
        if input.equal?(Undefined)
          evaluate
        else
          Undefined.default(type.call_unsafe(input)) { evaluate }
        end
      end

      # @param [Object] input
      #
      # @return [Object] value passed through {#type} or {#default} value
      #
      # @api private
      def call_safe(input = Undefined, &)
        if input.equal?(Undefined)
          evaluate
        else
          Undefined.default(type.call_safe(input, &)) { evaluate }
        end
      end

      # @api private
      def encode_unsafe(input, **)
        if input.equal?(Undefined)
          # Defaults complete missing external input; they have no key to remove
          # when internal data does not provide a value.
          raise CodecError.build(
            "default values cannot be encoded from an undefined input",
            direction: :encode
          )
        end

        type.encode_unsafe(input)
      end

      # @return [false]
      #
      # @api private
      def callable? = false

      # @api private
      def decode_unsafe(input = Undefined)
        if input.equal?(Undefined)
          evaluate
        else
          type.decode_unsafe(input)
        end
      end
    end
  end
end
