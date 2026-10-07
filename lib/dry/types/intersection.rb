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

      # Enable strict consistency checking for the two sides.
      #
      # @param [Boolean] enabled
      # @param [MergeRegistry] registry
      #
      # @return [Intersection]
      #
      # @api public
      def strict(enabled = true, registry: MergeRegistry.default)
        with(strict: enabled, merge_registry: registry)
      end

      # @param [Object] input
      #
      # @return [Object]
      #
      # @api private
      def call_unsafe(input)
        if strict?
          call_strict_unsafe(input)
        else
          merge_results(left.call_unsafe(input), right.call_unsafe(input))
        end
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

      # @param [Object] value
      #
      # @return [Boolean]
      #
      # @api private
      def primitive?(value)
        left.primitive?(value) && right.primitive?(value)
      end

      # @return [Boolean]
      #
      # @api private
      def strict? = options.fetch(:strict, false)

      private

      # @api private
      def after_initialize
        return unless strict?

        @left_validator = StrictMode.validator(left)
        @right_validator = StrictMode.validator(right)
      end

      # @api private
      def call_strict_unsafe(input)
        result = strict_result(input)
        raise result.error unless result.success?

        result.input
      end

      # @api private
      def try_sides(input, &block)
        return try_strict_sides(input, &block) if strict?

        results = []

        [left, right].each do |side|
          result = try_side(side, input, &block)
          return result if result.failure?

          results << result
        end

        Result::Success.new(merge_results(*results.map(&:input)))
      end

      # @api private
      def try_strict_sides(input, &block)
        result = strict_result(input)
        return yield(result) if result.failure? && block_given?

        result
      end

      # @api private
      def side_result(side, input)
        result = side.try(input)
        result.is_a?(Result) ? result : Result::Success.new(result)
      end

      # @api private
      def strict_result(input)
        left_result = side_result(left, input)
        right_result = side_result(right, input)

        unless left_result.success? && right_result.success?
          failure_result = left_result.failure? ? left_result : right_result
          error = IntersectionValidationError.new(
            EMPTY_ARRAY, left_result.input, right_result.input, failure_result.error
          )
          return Result::Failure.new(right_result.input, error)
        end

        begin
          merged = merge_strict(left_result.input, right_result.input)
        rescue IntersectionError => error
          return Result::Failure.new(right_result.input, error)
        end

        Result::Success.new(merged)
      end

      # @api private
      def merge_strict(left_result, right_result)
        merged = StrictMode.merge(
          left_result, right_result,
          left: left, right: right,
          registry: merge_registry,
          intersection: self
        )

        @left_validator.validate(merged, EMPTY_ARRAY, left_result, right_result)
        @right_validator.validate(merged, EMPTY_ARRAY, left_result, right_result)
        merged
      end

      # @api private
      def merge_registry
        options.fetch(:merge_registry) { MergeRegistry.default }
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
