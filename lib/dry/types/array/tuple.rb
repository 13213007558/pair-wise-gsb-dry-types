# frozen_string_literal: true

module Dry
  module Types
    class Array < Nominal
      class Tuple < Array
        attr_reader :prefix, :rest, :suffix, :tail

        def initialize(primitive, **options)
          @prefix = options.fetch(:prefix)
          @rest = options.fetch(:rest)
          @suffix = options.fetch(:suffix)
          @tail = options.fetch(:tail)
          super
          validate_definition
        end

        def call_unsafe(input)
          check_primitive(input)
          allocation = allocate(input)
          raise CoercionError, length_error(input).message unless allocation

          coerce(input, allocation, :call_unsafe)
        end

        def call_safe(input)
          return yield(input) unless primitive?(input)

          allocation = allocate(input)
          return yield(input) unless allocation

          coerce(input, allocation, :call_safe) { |output| return yield(output) }
        end

        def try(input, &block)
          unless primitive?(input)
            return tuple_failure(
              input,
              CoercionError.new("#{input.inspect} must be an instance of #{primitive}"),
              &block
            )
          end

          allocation = allocate(input)
          return tuple_failure(input, length_error(input), &block) unless allocation

          output = []

          each_slot(input, allocation) do |slot, index, slot_input|
            result = slot.try(slot_input)
            unless result.success?
              error = indexed_error(result.error, index, slot_input)
              return tuple_failure(output, error, &block)
            end

            output << result.input
          end

          success(output)
        end

        def lax
          Lax.new(
            Tuple.new(
              primitive,
              **options,
              prefix: prefix.map(&:lax),
              rest: rest&.lax,
              suffix: suffix.map(&:lax),
              tail: tail.map(&:lax),
              meta: meta
            )
          )
        end

        def to_ast(meta: true)
          [
            :tuple,
            [
              prefix.map { |type| type.to_ast(meta: meta) },
              rest ? rest.to_ast(meta: meta) : nil,
              suffix.map { |type| type.to_ast(meta: meta) },
              tail.map { |type| type.to_ast(meta: meta) },
              meta_ast(meta)
            ]
          ]
        end

        def constructor_type = ::Dry::Types::Array::Constructor

        private

        def validate_definition
          raise ::ArgumentError, "tuple prefix slots must be types" unless array_of_types?(prefix)
          raise ::ArgumentError, "tuple suffix slots must be types" unless array_of_types?(suffix)
          raise ::ArgumentError, "tuple tail slots must be types" unless array_of_types?(tail)
          unless tail.all?(&:default?)
            raise ::ArgumentError, "tuple tail slots must provide defaults"
          end
          raise ::ArgumentError, "tuple must define at least one slot" if empty?
        end

        def empty?
          rest.nil? && prefix.empty? && suffix.empty? && tail.empty?
        end

        def coerce(input, allocation, method)
          output = []

          each_slot(input, allocation) do |slot, _index, slot_input|
            coerced =
              if method == :call_unsafe
                slot.call_unsafe(slot_input)
              else
                slot.call_safe(slot_input) do
                  yield(output)
                  return
                end
              end

            output << coerced unless Undefined.equal?(coerced)
          end

          output
        end

        def each_slot(input, allocation)
          _prefix_size, rest_size, tail_size = allocation
          index = 0

          prefix.each do |slot|
            yield(slot, index, input[index])
            index += 1
          end

          if rest
            rest_size.times do
              yield(rest, index, input[index])
              index += 1
            end
          end

          suffix.each do |slot|
            yield(slot, index, input[index])
            index += 1
          end

          tail.size.times do |offset|
            slot_input = offset < tail_size ? input[index] : Undefined
            yield(tail[offset], index, slot_input)
            index += 1
          end
        end

        def allocate(input)
          return unless primitive?(input)
          minimum = minimum_size
          return if input.size < minimum
          return if rest.nil? && input.size > minimum + tail.size

          if rest
            allocate_rest(input)
          elsif input.size <= fixed_count + tail.size
            [prefix.size, 0, input.size - fixed_count]
          end
        end

        def allocate_rest(input)
          extra = input.size - fixed_count
          max_tail_size = [extra, tail.size].min
          tail_size =
            max_tail_size.downto(0).find do |candidate|
              allocation_valid?(input, extra - candidate, candidate)
            end || 0

          [prefix.size, extra - tail_size, tail_size]
        end

        def allocation_valid?(input, rest_size, tail_size)
          index = 0

          prefix.each do |slot|
            return false unless slot_matches?(slot, input[index])

            index += 1
          end

          rest_size.times do
            return false unless slot_matches?(rest, input[index])

            index += 1
          end

          suffix.each do |slot|
            return false unless slot_matches?(slot, input[index])

            index += 1
          end

          tail.first(tail_size).each do |slot|
            return false unless slot_matches?(slot, input[index])

            index += 1
          end

          true
        end

        def slot_matches?(slot, input)
          case slot
          when Dry::Types::Default
            slot_matches?(slot.type, input)
          when Dry::Types::Constructor
            slot_matches?(slot.type, input)
          when Constrained
            slot.rule[input]
          else
            true
          end
        end

        def length_error(input)
          range = rest ? "at least #{minimum_size}" : "#{minimum_size}..#{minimum_size + tail.size}"
          CoercionError.new("#{input.inspect} has #{input.size} elements, expected #{range}")
        end

        def fixed_count
          prefix.size + suffix.size
        end

        def minimum_size
          prefix.size + suffix.size
        end

        def check_primitive(input)
          return if primitive?(input)

          raise CoercionError, "#{input.inspect} must be an instance of #{primitive}"
        end

        def array_of_types?(value)
          value.is_a?(::Array) && value.all? { |type| type.respond_to?(:try) }
        end

        def indexed_error(error, index, input)
          case error
          when ConstraintError
            ConstraintError.new(error.result, input, meta: {index: index})
          when CoercionError
            CoercionError.new("[#{index}] #{error.message}", meta: {index: index})
          else
            error
          end
        end

        def tuple_failure(input, error)
          failure = failure(input, error)
          block_given? ? yield(failure) : failure
        end
      end
    end
  end
end
