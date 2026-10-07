# frozen_string_literal: true

module Dry
  module Types
    class Intersection
      # Registry for explicit, user-defined intersection result mergers.
      #
      # A merger must accept either two arguments or three arguments when it
      # also needs the intersection type. It must return a result that passes
      # the side-effect-free pure constraints of both types.
      #
      # @api public
      class MergeRegistry
        include ::Dry::Equalizer(:mergers, inspect: false, immutable: true)

        attr_reader :mergers

        # @return [MergeRegistry]
        #
        # @api public
        def self.default
          @default ||= new
        end

        # Register a merger on the process-wide registry.
        #
        # Prefer passing a registry to {Intersection#strict} in library code and
        # tests so that the global registry remains isolated.
        #
        # @return [void]
        #
        # @api public
        def self.register(pair, merger = nil, checker = nil, &block)
          @default = default.register(pair, merger || block, checker)
          nil
        end

        # Remove a previously registered merger from the process-wide registry.
        #
        # @return [void]
        #
        # @api public
        def self.unregister(pair)
          @default = default.unregister(pair)
          nil
        end

        # @param [Hash{Array => #call}] mergers
        #
        # @api private
        def initialize(mergers = EMPTY_HASH)
          @mergers = mergers.dup.freeze
          freeze
        end

        # Register a result merger and, optionally, a side-effect-free checker.
        #
        # The checker receives the merged result and must return true or false.
        # It is intentionally not given the constructors, because running them
        # again could trigger side effects.
        #
        # @param [Array(Dry::Types::Type, Dry::Types::Type)] pair
        # @param [#call] merger
        # @param [#call, nil] checker
        #
        # @return [MergeRegistry]
        #
        # @api public
        def register(pair, merger = nil, checker = nil, &block)
          merger ||= block

          left, right = pair

          unless left.is_a?(Type) && right.is_a?(Type)
            raise ::ArgumentError, "a pair of types is required"
          end

          unless merger.respond_to?(:call)
            raise ::ArgumentError, "merger must respond to #call"
          end

          if checker && !checker.respond_to?(:call)
            raise ::ArgumentError, "checker must respond to #call"
          end

          self.class.new(@mergers.merge(key_for(left, right) => [merger, checker].freeze))
        end

        # Remove a registered result merger.
        #
        # @param [Array(Dry::Types::Type, Dry::Types::Type)] pair
        #
        # @return [MergeRegistry]
        #
        # @api public
        def unregister(pair)
          left, right = pair
          self.class.new(@mergers.except(key_for(left, right)))
        end

        # Whether any merger is registered.
        #
        # @return [Boolean]
        #
        # @api private
        def empty? = @mergers.empty?

        # @param [Dry::Types::Type] left
        # @param [Dry::Types::Type] right
        #
        # @return [Array<#call>, nil]
        #
        # @api private
        def lookup(left, right)
          @mergers[key_for(left, right)]
        end

        private

        # @api private
        def key_for(left, right)
          [left.pristine, right.pristine]
        end
      end
    end
  end
end
