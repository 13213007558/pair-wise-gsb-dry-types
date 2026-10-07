# frozen_string_literal: true

module Dry
  module Types
    # Common Type module denoting an object is a Type
    #
    # @api public
    module Type
      extend ::Dry::Core::Deprecations[:"dry-types"]

      deprecate(:safe, :lax)

      # Whether a value is a valid member of the type
      #
      # @return [Boolean]
      #
      # @api private
      def valid?(input = Undefined)
        call_safe(input) { return false }
        true
      end
      # Anything can be coerced matches
      alias_method :===, :valid?

      # Whether the type can be used as both sides of a codec
      #
      # @return [Boolean]
      #
      # @api public
      def codec? = false

      # @return [Boolean]
      #
      # @api public
      def decoder? = true

      # @return [Boolean]
      #
      # @api public
      def encoder? = true

      # Decode an external representation
      #
      # @return [Object]
      #
      # @api public
      def decode(input = Undefined, **_options, &block)
        block_given? ? decode_safe(input, &block) : decode_unsafe(input)
      end

      # Encode an internal value
      #
      # @return [Object]
      #
      # @api public
      def encode(input = Undefined, as: nil, &block)
        options = as.nil? ? EMPTY_HASH : {as: as}
        block_given? ? encode_safe(input, **options, &block) : encode_unsafe(input, **options)
      end

      # @api private
      def decode_unsafe(input) = call_unsafe(input)

      # @api private
      def decode_safe(input, &block)
        decode_unsafe(input)
      rescue CodecError => exception
        block.call(exception)
      end

      # @api private
      def encode_unsafe(input, **_options) = call_unsafe(input)

      # @api private
      def encode_safe(input, **options, &block)
        encode_unsafe(input, **options)
      rescue CodecError => exception
        block.call(exception)
      end

      # Ensure a child type declares both codec directions
      #
      # @raise [CodecError]
      #
      # @api private
      def assert_direction!(direction)
        method_name = direction == :decode ? :decoder? : :encoder?
        return self if public_send(method_name)

        raise CodecError.build(
          "#{inspect} is not a codec; one-way constructors require an explicit inverse",
          direction: direction
        )
      end

      # Apply type to a value
      #
      # @overload call(input = Undefined)
      #   Possibly unsafe coercion attempt. If a value doesn't
      #   match the type, an exception will be raised.
      #
      #   @param [Object] input
      #   @return [Object]
      #
      # @overload call(input = Undefined)
      #   When a block is passed, {#call} will never throw an exception on
      #   failed coercion, instead it will call the block.
      #
      #   @param [Object] input
      #   @yieldparam [Object] output Partially coerced value
      #   @return [Object]
      #
      # @api public
      def call(input = Undefined, &)
        if block_given?
          call_safe(input, &)
        else
          call_unsafe(input)
        end
      end
      alias_method :[], :call
    end
  end
end
