# frozen_string_literal: true

require "dry/core/equalizer"
require "dry/types/options"
require "dry/types/meta"

module Dry
  module Types
    # Intersection type
    #
    # @api public
    class Intersection
      include Composition

      def self.operator = :&

      # @param [Object] input
      #
      # @return [Object]
      #
      # @api private
      def call_unsafe(input)
        merge_results(left.call_unsafe(input), right.call_unsafe(input))
      end

      # @param [Object] input
      #
      # @return [Object]
      #
      # @api private
      def call_safe(input, &) = try_sides(input, &).input

      # @param [Object] input
      #
      # @api public
      def try(input)
        try_sides(input) do |failure|
          if block_given?
            yield(failure)
          else
            failure
          end
        end
      end

      # @return [Boolean]
      #
      # @api public
      def encodable?
        left.encodable? && right.encodable?
      end

      # @api private
      def decode_unsafe(input) = call_unsafe(input)

      # @api private
      def encode_unsafe(input)
        merge_results(left.encode_unsafe(input), right.encode_unsafe(input))
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
        left.primitive?(value) && right.primitive?(value)
      end

      private

      # @api private
      def try_sides(input, &block)
        results = []

        [left, right].each do |side|
          result = try_side(side, input, &block)
          return result if result.failure?

          results << result
        end

        Result::Success.new(merge_results(*results.map(&:input)))
      end

      # @api private
      def try_side(side, input)
        failure = nil

        result = side.try(input) do |f|
          failure = f
          yield(f)
        end

        if result.is_a?(Result)
          result
        elsif failure
          Result::Failure.new(result, failure)
        else
          Result::Success.new(result)
        end
      end

      # @api private
      def merge_results(left_result, right_result)
        case left_result
        when ::Array
          left_result.zip(right_result).map { merge_results(_1, _2) }
        when ::Hash
          left_result.merge(right_result)
        else
          left_result
        end
      end
    end
  end
end
