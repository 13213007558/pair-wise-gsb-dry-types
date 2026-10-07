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

      # Encode an internal value to its external representation
      #
      # Plain types are one-directional: their external representation is the
      # value itself, so the default encoding validates the value and returns
      # it as-is. {Codec} types override this with an explicit encoder and
      # {Constructor} types raise a {CodecError} because the inverse of an
      # arbitrary constructor cannot be guessed
      #
      # @param [Object] input
      #
      # @return [Object]
      #
      # @api public
      def encode(input) = call_unsafe(input)

      # Safe encoding attempt, mirroring {#try} for the encoding direction
      #
      # @param [Object] input
      #
      # @yieldparam [Failure] failure
      # @yieldreturn [Object]
      #
      # @return [Result::Success, Result::Failure]
      # @return [Object] if encoding fails and a block is given
      #
      # @api public
      def try_encode(input)
        Result::Success.new(encode(input))
      rescue CoercionError => exception
        failure = Result::Failure.new(input, exception)
        block_given? ? yield(failure) : failure
      end

      # Whether a value can be encoded by the type. Used by sum types to
      # pick an encoding branch
      #
      # @param [Object] input
      #
      # @return [Boolean]
      #
      # @api public
      def accepts_encoding?(input) = valid?(input)
    end
  end
end
