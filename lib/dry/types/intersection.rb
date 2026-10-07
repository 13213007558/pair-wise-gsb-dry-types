# frozen_string_literal: true

require "dry/core/equalizer"
require "dry/types/options"
require "dry/types/meta"
require "dry/types/intersection/strict"

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
        if strict?
          Strict.new(self, input).call
        else
          merge_results(left.call_unsafe(input), right.call_unsafe(input))
        end
      end

      # @param [Object] input
      #
      # @return [Object]
      #
      # @api private
      def call_safe(input, &block)
        result = try(input)
        result.success? ? result.input : yield(result.input)
      end

      # @param [Object] input
      #
      # @api public
      def try(input)
        if strict?
          begin
            Result::Success.new(Strict.new(self, input).call)
          rescue Strict::Error => failure
            failure_result = Result::Failure.new(input, failure)
            block_given? ? yield(failure_result) : failure_result
          end
        else
          try_sides(input) do |failure|
            block_given? ? yield(failure) : failure
          end
        end
      end

      def strict(strict = true)
        with(strict: strict)
      end

      def strict? = options.fetch(:strict, false)

      def self.register_merger(...) = Strict.register_merger(...)

      def with(**new_options)
        type = self.class.new(left, right, **options, meta: meta, **new_options)
        type.assert_strict_support! if type.strict? && new_options.key?(:strict)
        type
      end

      def assert_strict_support!
        unless Strict.supported_combination?(left, right)
          raise Strict::UnsupportedCombination.new(left, right)
        end
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
