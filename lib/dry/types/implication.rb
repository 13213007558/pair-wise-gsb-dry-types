# frozen_string_literal: true

module Dry
  module Types
    # Implication type
    #
    # @api public
    class Implication
      include Composition

      def self.operator = :>

      # @param [Object] input
      #
      # @return [Object]
      #
      # @api private
      def call_unsafe(input)
        if left.try(input).success?
          right.call_unsafe(input)
        else
          input
        end
      end

      # @param [Object] input
      #
      # @return [Object]
      #
      # @api private
      def call_safe(input, &)
        if left.try(input).success?
          right.call_safe(input, &)
        else
          input
        end
      end

      # @param [Object] input
      #
      # @api public
      def try(input, &)
        if left.try(input).success?
          right.try(input, &)
        else
          Result::Success.new(input)
        end
      end

      # @return [Boolean]
      #
      # @api public
      def encodable?
        right.encodable?
      end

      # @api private
      def decode_unsafe(input) = call_unsafe(input)

      # @api private
      def encode_unsafe(input)
        if left.try(input).success?
          right.encode_unsafe(input)
        else
          input
        end
      end

      # @api private
      def decode_safe(input)
        decode_unsafe(input)
      rescue CodecError => error
        yield(error)
      end

      # @api private
      def encode_safe(input)
        encode_unsafe(input)
      rescue CodecError => error
        yield(error)
      end

      # @param [Object] value
      #
      # @return [Boolean]
      #
      # @api private
      def primitive?(value)
        if left.primitive?(value)
          right.primitive?(value)
        else
          true
        end
      end
    end
  end
end
