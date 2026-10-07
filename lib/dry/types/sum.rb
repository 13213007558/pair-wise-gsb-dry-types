# frozen_string_literal: true

module Dry
  module Types
    # Sum type
    #
    # Sum types try each constituent type from left to right and return the result
    # from the first successful type. If all types fail, the error from the rightmost
    # (last attempted) type is raised, not necessarily the most "relevant" error.
    #
    # @example
    #   # Given: FixedAmount | Percentage
    #   # Input: { type: "fixed", value: -1.1 }
    #   # FixedAmount fails on value constraint, Percentage fails on type mismatch
    #   # Error raised will be from Percentage (rightmost), not FixedAmount
    #
    # @api public
    class Sum
      include Composition

      def self.operator = :|

      # @return [Boolean]
      #
      # @api public
      def optional? = primitive?(nil)

      # @param [Object] input
      #
      # @return [Object]
      #
      # @note Tries left type first, then right type. If both fail, raises the
      #   error from the right (last attempted) type for performance reasons.
      #
      # @api private
      def call_unsafe(input)
        left.call_safe(input) { right.call_unsafe(input) }
      end

      # @param [Object] input
      #
      # @return [Object]
      #
      # @api private
      def call_safe(input, &block)
        left.call_safe(input) { right.call_safe(input, &block) }
      end

      # @param [Object] input
      #
      # @api public
      def try(input)
        left.try(input) do
          right.try(input) do |failure|
            if block_given?
              yield(failure)
            else
              failure
            end
          end
        end
      end

      # @return [Boolean]
      #
      # @api public
      def codec? = left.codec? && right.codec?

      # @return [Boolean]
      #
      # @api public
      def decoder? = left.decoder? && right.decoder?

      # @return [Boolean]
      #
      # @api public
      def encoder? = left.encoder? && right.encoder?

      # @api private
      def decode_unsafe(input)
        assert_codec!(:decode)
        candidates = decode_candidates(input, each_codec_branch)

        if candidates.empty?
          raise CodecError.build(
            "no sum branch accepts #{input.inspect}",
            direction: :decode
          )
        end

        if candidates.size > 1
          raise AmbiguousCodecError.new(
            "ambiguous decode: branches #{branch_labels(candidates).inspect} all accept #{input.inspect}",
            branches: candidates.map { |branch, _| branch },
            direction: :decode
          )
        end

        candidates.values.first
      end

      # @api private
      def encode_unsafe(input, as: nil)
        assert_codec!(:encode)
        branches = each_codec_branch
        matches = branches.select { |branch| internal_valid?(branch, input) }

        unless as.nil?
          matches = matches.select { |branch| branch[:label].include?(as) }
        end

        if matches.empty?
          raise CodecError.build(
            "no sum branch accepts #{input.inspect}",
            direction: :encode
          )
        end

        if matches.size > 1
          labels = branch_labels(matches).inspect
          message = [
            "ambiguous encode: branches #{labels} all accept #{input.inspect};",
            "use an explicit tag"
          ].join(" ")
          raise AmbiguousCodecError.new(
            message,
            branches: matches.map { |branch| branch[:label] },
            direction: :encode
          )
        end

        branch = matches.first
        encoded = encode_branch(branch, input)
        encoded
      end

      # @param [Object] value
      #
      # @return [Boolean]
      #
      # @api private
      def primitive?(value)
        left.primitive?(value) || right.primitive?(value)
      end

      # Manage metadata to the type. If the type is an optional, #meta delegates
      # to the right branch
      #
      # @see [Meta#meta]
      #
      # @api public
      def meta(data = Undefined)
        if Undefined.equal?(data)
          optional? ? right.meta : super
        elsif optional?
          self.class.new(left, right.meta(data), **options)
        else
          super
        end
      end

      # @param [Hash] options
      #
      # @return [Constrained,Sum]
      #
      # @see Builder#constrained
      #
      # @api public
      def constrained(...)
        if optional?
          right.constrained(...).optional
        else
          super
        end
      end

      private

      def assert_codec!(direction)
        return if public_send(direction == :decode ? :decoder? : :encoder?)

        raise CodecError.build("all sum branches must be codecs", direction: direction)
      end

      def decode_candidates(input, branches = each_codec_branch)
        branches.each_with_object({}) do |branch, candidates|
          decoded = branch[:codec].decode_unsafe(input)
          candidates[branch[:label]] = decoded
        rescue CodecError
          next
        end
      end

      def each_codec_branch(type = self, prefix = EMPTY_ARRAY)
        case type
        when Codec::Tagged
          [{label: prefix + [type.label], codec: type}]
        when Sum
          each_codec_branch(type.left, prefix + [:left]) +
            each_codec_branch(type.right, prefix + [:right])
        when Codec, Schema, Array::Member, Nominal
          [{label: prefix + [type.name.to_sym], codec: type}]
        when Decorator
          wrapped = type.type
          each_codec_branch(wrapped, prefix).map do |branch|
            branch.merge(codec: type)
          end
        else
          []
        end
      end

      def branch_labels(branches)
        branches = branches.keys if branches.is_a?(::Hash)
        branches.map { |branch| branch.map(&:inspect).join("/") }
      end

      def internal_valid?(branch, value)
        codec = branch[:codec]
        internal_type =
          case codec
          when Codec::Tagged then codec.type.internal
          when Codec then codec.internal
          when Default then codec.type
          else codec
          end
        internal_value?(internal_type, value)
      rescue StandardError
        false
      end

      def internal_value?(type, value)
        return type.valid?(value) if type.is_a?(::Dry::Types::Constrained)

        type.primitive?(value)
      end

      def encode_branch(branch, input)
        case branch[:codec]
        when Codec::Tagged then branch[:codec].encode_unsafe(input)
        else branch[:codec].encode_unsafe(input)
        end
      end
    end
  end
end
