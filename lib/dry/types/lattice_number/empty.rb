# frozen_string_literal: true

module Dry
  module Types
    class LatticeNumber
      # An empty lattice type. Every value fails validation and intersections
      # with it short-circuit to another empty type.
      #
      # @api public
      class Empty < LatticeNumber
        # @return [Array<LatticeNumber>] incompatible sides of the intersection
        attr_reader :sides

        # @api private
        def initialize(left = nil, right = nil)
          @sides = [left, right].freeze
          @origin = 0r
          @step = 1r
          @lower_bound = 1r
          @upper_bound = 0r
          @exclude_begin = false
          @exclude_end = true
          @rounding = nil
          @tie = :up
          @options = EMPTY_HASH
          @meta = EMPTY_HASH
          freeze
        end

        # @return [true]
        def empty? = true

        # @return [nil]
        def minimum_point = nil

        # @param [Object] input
        #
        # @raise [ConstraintError]
        #
        # @api private
        def call_unsafe(input)
          raise ConstraintError.new("#{inspect} has no valid values", input)
        end

        # @param [Object] input
        #
        # @return [Object]
        #
        # @api private
        def call_safe(input, &block)
          return yield if block_given?

          input
        end

        # @param [Object] input
        #
        # @return [Result::Failure]
        #
        # @api public
        def try(input, &)
          failure = failure(
            input,
            ConstraintError.new("#{inspect} has no valid values", input)
          )
          block_given? ? yield(failure) : failure
        end

        # @return [Empty]
        #
        # @api public
        def intersect(other)
          other.is_a?(Empty) ? self : Empty.new(self, other)
        end

        # Restricting an empty lattice stays empty
        #
        # @return [Empty]
        #
        # @api public
        def constrain_range(*) = self

        # @return [Range]
        #
        # @api public
        def range
          ::Range.new(1r, 0r, true)
        end

        # @return [false]
        def ==(other) = other.is_a?(Empty)
        alias_method :eql?, :==

        # @return [Integer]
        def hash = [self.class, :empty].hash

        # @see LatticeNumber#to_ast
        def to_ast(meta: true)
          [:lattice_number_empty, [meta ? self.meta : EMPTY_HASH]]
        end
      end
    end
  end
end
