# frozen_string_literal: true

module Dry
  module Types
    # Tuple types describe arrays with a fixed structure:
    #
    #   [head..., rest..., tail..., optional...]
    #
    # - head:     required slots bound to the first elements, in order
    # - rest:     an optional single type consuming the variable-length middle
    # - tail:     required slots bound right after the head/rest region
    # - optional: trailing slots that may be absent from the input
    #
    # Every slot is a full type of its own, so slots can have their own
    # constructors, constraints and default values.
    #
    # Assignment rules:
    #
    # - input length is validated before any member is converted:
    #   at least `head.size + tail.size` elements and, unless a rest type
    #   is present, at most `head.size + tail.size + optional.size`
    # - a rest type combined with optional trailing slots is ambiguous
    #   (both compete for the unbounded tail region) and is rejected
    #   when the tuple is defined
    # - with a rest type, tail slots bind to the last elements and rest
    #   consumes everything in between
    # - with optional slots, they bind the remaining elements in order;
    #   absent slots are omitted from the output unless their type has
    #   a default value, in which case the default is used
    #
    # @api public
    class Tuple < Array
      # @return [Array<Type>] required leading slots
      attr_reader :head

      # @return [Type, nil] type of the variable-length middle
      attr_reader :rest

      # @return [Array<Type>] required trailing slots
      attr_reader :tail

      # @return [Array<Type>] optional trailing slots
      attr_reader :optional

      # @param [Class] primitive
      # @param [Hash] options
      #
      # @option options [Array<Type>] :head
      # @option options [Type, nil] :rest
      # @option options [Array<Type>] :tail
      # @option options [Array<Type>] :optional
      #
      # @api private
      def initialize(primitive, **options)
        @head = options.fetch(:head).map { |slot| slot_type(slot) }.freeze
        @rest = options[:rest] && slot_type(options[:rest])
        @tail = options.fetch(:tail).map { |slot| slot_type(slot) }.freeze
        @optional = options.fetch(:optional).map { |slot| slot_type(slot) }.freeze

        if @rest && !@optional.empty?
          raise ::ArgumentError,
                "tuple cannot combine a rest type with optional trailing slots: " \
                "assigning input elements would be ambiguous"
        end

        super
      end

      # @return [Integer] minimum number of input elements
      #
      # @api private
      def min_size = head.size + tail.size

      # @param [Object] input
      #
      # @return [Array]
      #
      # @api private
      def call_unsafe(input)
        if primitive?(input)
          assert_length(input.size)

          output = []

          each_slot(input) do |slot, index|
            coerced = slot.call_unsafe(input[index])
            output << coerced unless Undefined.equal?(coerced)
          end

          append_absent_defaults(input.size, output)

          output
        else
          super
        end
      end

      # @param [Object] input
      #
      # @return [Array]
      #
      # @api private
      def call_safe(input)
        if primitive?(input)
          return yield if length_error(input.size)

          failed = false
          output = []

          each_slot(input) do |slot, index|
            coerced = slot.call_safe(input[index]) { |out = input[index]|
              failed = true
              out
            }
            output << coerced unless Undefined.equal?(coerced)
          end

          append_absent_defaults(input.size, output)

          failed ? yield(output) : output
        else
          yield
        end
      end

      # @param [Array, Object] input
      # @param [#call,nil] block
      #
      # @yieldparam [Failure] failure
      # @yieldreturn [Result]
      #
      # @return [Result,Logic::Result]
      #
      # @api public
      def try(input, &block)
        if primitive?(input)
          if (error = length_error(input.size))
            failure = failure(input, CoercionError.new(error))
            return block ? yield(failure) : failure
          end

          output = []

          each_slot(input) do |slot, index|
            result = slot.try(input[index])

            if result.success?
              output << result.input unless Undefined.equal?(result.input)
            else
              error = TupleError.new(index, result.error)
              failure = failure(input, error)
              return block ? yield(failure) : failure
            end
          end

          append_absent_defaults(input.size, output)

          success(output)
        else
          failure = failure(input, CoercionError.new("#{input} is not an array"))
          block ? yield(failure) : failure
        end
      end

      # Build a lax type
      #
      # @return [Lax]
      #
      # @api public
      def lax
        Lax.new(
          Tuple.new(
            primitive,
            **options,
            head: head.map(&:lax),
            rest: rest&.lax,
            tail: tail.map(&:lax),
            optional: optional.map(&:lax),
            meta: meta
          )
        )
      end

      # @see Nominal#to_ast
      #
      # @api public
      def to_ast(meta: true)
        spec = {
          head: head.map { |slot| slot_ast(slot, meta) },
          rest: rest && slot_ast(rest, meta),
          tail: tail.map { |slot| slot_ast(slot, meta) },
          optional: optional.map { |slot| slot_ast(slot, meta) }
        }

        [:tuple, [spec, meta_ast(meta)]]
      end

      private

      # Resolve a slot to a type
      #
      # @api private
      def slot_type(slot)
        case slot
        when ::String then Types[slot]
        else slot
        end
      end

      # @api private
      def slot_ast(slot, meta)
        if slot.respond_to?(:to_ast)
          slot.to_ast(meta: meta)
        else
          slot
        end
      end

      # @return [String, nil] error message when the length is invalid
      #
      # @api private
      def length_error(size)
        if size < min_size
          "tuple has #{size} elements, at least #{min_size} expected"
        elsif rest.nil? && size > min_size + optional.size
          "tuple has #{size} elements, at most #{min_size + optional.size} expected"
        end
      end

      # @raise [CoercionError]
      #
      # @api private
      def assert_length(size)
        if (error = length_error(size))
          raise CoercionError, error
        end
      end

      # Yield [slot, input_index] pairs for every element of the input
      #
      # @api private
      def each_slot(input)
        size = input.size
        head_size = head.size
        tail_size = tail.size

        head.each_with_index do |slot, index|
          yield slot, index
        end

        if rest
          (size - head_size - tail_size).times do |offset|
            yield rest, head_size + offset
          end

          tail.each_with_index do |slot, offset|
            yield slot, size - tail_size + offset
          end
        else
          tail.each_with_index do |slot, offset|
            yield slot, head_size + offset
          end

          (size - head_size - tail_size).times do |offset|
            yield optional[offset], head_size + tail_size + offset
          end
        end
      end

      # Append default values of absent optional slots to the output
      #
      # @api private
      def append_absent_defaults(input_size, output)
        return output if rest || optional.empty?

        absent = optional[(input_size - min_size)..] || EMPTY_ARRAY

        absent.each do |slot|
          output << slot.call(Undefined) if slot.respond_to?(:default?) && slot.default?
        end

        output
      end
    end
  end
end
