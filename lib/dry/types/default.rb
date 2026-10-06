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
      include Meta
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
        @meta = type.meta.freeze if @meta.empty? && !type.meta.empty?
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

      # @return [false]
      #
      # @api private
      def callable? = false

      # @see Nominal#to_ast
      #
      # @api public
      def to_ast(meta: true)
        [:default, [type.to_ast(meta: meta), default_ast, meta ? self.meta : EMPTY_HASH]]
      end

      private

      def default_ast
        case value
        when ::Method
          [
            :callable_default,
            [value.parameters.empty?, [:method, value.receiver, value.name]]
          ]
        when ::Proc
          [:callable_default, [value.parameters.empty?, [:callable, value]]]
        when ::Object
          value.respond_to?(:to_ast) ? value.to_ast : [:value, value]
        end
      end
    end
  end
end
