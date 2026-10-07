# frozen_string_literal: true

module Dry
  module Types
    # Codec types pair decoding (external representation -> internal value)
    # with encoding (internal value -> external representation)
    #
    # Decoding works like a constructor: {#call}, {#call_safe} and {#try}
    # validate the input against the external type, apply the decoder and
    # validate the result against the internal type. Encoding goes the other
    # way via {#encode} and {#try_encode}: the value is checked against the
    # internal type, transformed by the encoder and the result is checked
    # against the external type
    #
    # @example
    #   decimal = Dry::Types::Codec.new(
    #     Dry::Types["strict.decimal"],
    #     external: Dry::Types["strict.string"],
    #     encoder: -> decimal { decimal.to_s("F") },
    #     fn: -> string { BigDecimal(string) }
    #   )
    #
    #   decimal.("12.34") # => 0.1234e2
    #   decimal.encode(BigDecimal("12.34")) # => "12.34"
    #
    # @api public
    class Codec < Constructor
      # @return [Type] type of the external representation
      attr_reader :external

      # @return [Function] encoder mapping internal values to the external representation
      attr_reader :encoder

      # @param [Builder, Object] input internal type or primitive class
      # @param [Builder, Type] external external type or primitive class
      # @param [#call] encoder maps internal values to the external representation
      # @param [#call, nil] fn decoder, falls back to the block
      # @param [Hash] options
      # @param [#call, nil] block decoder
      #
      # @api public
      def self.new(input, external:, encoder:, fn: Undefined, **options, &block)
        external_type = external.is_a?(Builder) ? external : Nominal.new(external)

        super(
          input,
          fn: fn,
          **options,
          external: external_type,
          encoder: Function[encoder],
          &block
        )
      end

      # @param [Type] type internal type
      # @option options [Type] :external
      # @option options [Function] :encoder
      # @option options [Function] :fn decoder
      # @param [Hash] options
      #
      # @api private
      def initialize(type, external:, encoder:, **options)
        @external = external
        @encoder = encoder

        super(type, external: external, encoder: encoder, **options)
      end

      # Decode an external representation into an internal value
      #
      # @param [Object] input
      #
      # @return [Object]
      #
      # @api private
      def call_unsafe(input)
        type.call_unsafe(fn.(external.call_unsafe(input)))
      rescue CodecError
        raise
      rescue CoercionError => exception
        raise CodecError.new(exception.message, direction: :decode)
      end

      # @param [Object] input
      #
      # @return [Object]
      #
      # @api private
      def call_safe(input)
        external_value = external.call_safe(input) { return yield(input) }
        decoded = fn.(external_value) { |output = input| return yield(output) }
        type.call_safe(decoded) { |output = decoded| yield(output) }
      end

      # @param [Object] input
      # @param [#call,nil] block
      #
      # @return [Logic::Result, Types::Result]
      # @return [Object] if block given and try fails
      #
      # @api public
      def try(input, &)
        value = call_unsafe(input)
      rescue CoercionError => exception
        failure = failure(input, exception)
        block_given? ? yield(failure) : failure
      else
        success(value)
      end

      # Encode an internal value to its external representation
      #
      # The value is checked against the internal type before the encoder
      # runs, and the encoder output is checked against the external type
      #
      # @param [Object] input
      #
      # @return [Object]
      #
      # @api public
      def encode(input)
        external.call_unsafe(encoder.(type.call_unsafe(input)))
      rescue CodecError
        raise
      rescue CoercionError => exception
        raise CodecError.new(exception.message, direction: :encode)
      end

      # Whether a value satisfies the internal constraint and can therefore
      # be encoded
      #
      # @param [Object] input
      #
      # @return [Boolean]
      #
      # @api public
      def accepts_encoding?(input) = type.valid?(input)

      # Defaults of codecs are internal values, so they are checked against
      # the internal constraint rather than the external one
      #
      # @return [Boolean]
      #
      # @api private
      def valid_default?(value) = accepts_encoding?(value)

      # @return [Class]
      #
      # @api private
      def constructor_type = Codec

      # Use the given value when decoding fails. Fallback values are
      # internal values, so they are checked against the internal constraint
      #
      # @param [Object] value
      # @option [Boolean] shared Whether it is safe to share the value across type applications
      # @param [#call,nil] block fallback
      #
      # @return [Codec]
      #
      # @api public
      def fallback(value = Undefined, shared: false, &block)
        if Undefined.equal?(value) && !block_given?
          raise ::ArgumentError, "fallback value or a block must be given"
        end

        if !block_given? && !valid_default?(value)
          raise ConstraintError.new(
            "fallback value #{value.inspect} violates constraints",
            value
          )
        end

        unless value.frozen? || shared
          where = Core::Deprecations::STACK.()
          Core::Deprecations.warn(
            "#{value.inspect} is mutable. " +            "Be careful: types will return the same instance of the fallback " +            "value every time. Call `.freeze` when setting the fallback " +            "or pass `shared: true` to discard this warning." +            "\n#{where}",
            tag: :"dry-types"
          )
        end

        decode = method(:call_unsafe)

        with(fn: -> input {
          begin
            decode.(input)
          rescue CoercionError
            block ? block.(input) : value
          end
        })
      end

      # Manage metadata on the internal type, keeping the codec intact
      #
      # @see Dry::Types::Meta#meta
      #
      # @api public
      def meta(data = Undefined)
        if Undefined.equal?(data)
          type.meta
        else
          self.class.new(type.meta(data), **options)
        end
      end

      # Build a lax type
      #
      # @return [Lax]
      #
      # @api public
      def lax = Lax.new(self)

      # @see Nominal#to_ast
      #
      # @api public
      def to_ast(meta: true)
        [:codec, [type.to_ast(meta: meta), external.to_ast(meta: meta), fn.to_ast, encoder.to_ast]]
      end
    end
  end
end
