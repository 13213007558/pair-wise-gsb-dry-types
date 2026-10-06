# frozen_string_literal: true

module Dry
  module Types
    # Array type can be used to define an array with optional member type
    #
    # @api public
    class Array < Nominal
      # Build an array type with a member type
      #
      # @param [Type,#call] type
      #
      # @return [Array::Member]
      #
      # @api public
      def of(type)
        Array::Member.new(primitive, **options, member: resolve_type(type))
      end

      def tuple(*prefix, **options)
        rest_type = options.fetch(:rest, Undefined)
        suffix_types = slot_types(options.fetch(:suffix, EMPTY_ARRAY))
        tail_types = slot_types(options.fetch(:tail, EMPTY_ARRAY))
        resolved_prefix = prefix.map { |type| resolve_type(type) }
        resolved_rest = Undefined.default(rest_type, nil)
        resolved_rest = resolve_type(resolved_rest) if resolved_rest
        resolved_suffix = suffix_types.map { |type| resolve_type(type) }
        resolved_tail = tail_types.map { |type| resolve_type(type) }

        Array::Tuple.new(
          primitive,
          **options.except(:rest, :suffix, :tail),
          prefix: resolved_prefix,
          rest: resolved_rest,
          suffix: resolved_suffix,
          tail: resolved_tail
        )
      end

      # @api private
      def constructor_type
        ::Dry::Types::Array::Constructor
      end

      private

      def slot_types(value)
        value.is_a?(::Array) ? value : [value]
      end

      def resolve_type(type)
        case type
        when ::String then Types[type]
        else type
        end
      end
    end
  end
end
