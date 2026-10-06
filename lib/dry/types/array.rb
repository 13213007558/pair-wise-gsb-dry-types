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
        member =
          case type
          when ::String then Types[type]
          else type
          end

        Array::Member.new(primitive, **options, member: member)
      end

      # Build a tuple type with fixed head/tail slots, an optional rest
      # type for the variable-length middle and optional trailing slots
      #
      # @param [Array<Type, String>] head required leading slot types
      # @param [Type, String, nil] rest type of the variable-length middle
      # @param [Array<Type, String>] tail required trailing slot types
      # @param [Array<Type, String>] optional trailing slots that may be absent
      #
      # @return [Tuple]
      #
      # @api public
      def tuple(*head, rest: nil, tail: EMPTY_ARRAY, optional: EMPTY_ARRAY)
        Tuple.new(
          primitive,
          **options,
          head: head,
          rest: rest,
          tail: tail,
          optional: optional
        )
      end

      # @api private
      def constructor_type
        ::Dry::Types::Array::Constructor
      end
    end
  end
end
