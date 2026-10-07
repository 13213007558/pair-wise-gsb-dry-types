# frozen_string_literal: true

module Dry
  module Types
    class Array < Nominal
      # Member arrays define their member type that is applied to each element
      #
      # @api public
      class Member < Array
        # @return [Type]
        attr_reader :member

        # @param [Class] primitive
        # @param [Hash] options
        #
        # @option options [Type] :member
        #
        # @api private
        def initialize(primitive, **options)
          @member = options.fetch(:member)
          super
        end

        # @param [Object] input
        #
        # @return [Array]
        #
        # @api private
        def call_unsafe(input)
          if primitive?(input)
            input.each_with_object([]) do |el, output|
              coerced = member.call_unsafe(el)

              output << coerced unless Undefined.equal?(coerced)
            end
          else
            super
          end
        end

        # @param [Object] input
        # @return [Array]
        #
        # @api private
        def call_safe(input)
          if primitive?(input)
            failed = false

            result = input.each_with_object([]) do |el, output|
              coerced = member.call_safe(el) { |out = el|
                failed = true
                out
              }

              output << coerced unless Undefined.equal?(coerced)
            end

            failed ? yield(result) : result
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
        def try(input, &block) # rubocop:disable Metrics/PerceivedComplexity
          if primitive?(input)
            output = []

            result = input.map { |el| member.try(el) }
            result.each do |r|
              output << r.input unless Undefined.equal?(r.input)
            end

            if result.all?(&:success?)
              success(output)
            else
              error = result.find(&:failure?).error
              failure = failure(output, error)
              block ? yield(failure) : failure
            end
          else
            failure = failure(input, CoercionError.new("#{input} is not an array"))
            block ? yield(failure) : failure
          end
        end

        # @return [Boolean]
        #
        # @api public
        def codec? = member.codec?

        # @return [Boolean]
        #
        # @api public
        def decoder? = member.decoder?

        # @return [Boolean]
        #
        # @api public
        def encoder? = member.encoder?

        # @return [Boolean]
        #
        # @api private
        def conforms_without_codec?(input, direction)
          return false unless primitive?(input)

          input.all? { |element| externally_conforms?(member, element) }
        end

        # @api private
        def decode_unsafe(input)
          unless primitive?(input)
            raise CodecError.build("#{input.inspect} must be an array", direction: :decode)
          end
          input.each_with_index.map do |element, index|
            member.decode_unsafe(element)
          rescue CodecError => exception
            raise exception.with_path(index, :decode)
          end
        end

        # @api private
        def encode_unsafe(input, **)
          unless primitive?(input)
            raise CodecError.build("#{input.inspect} must be an array", direction: :encode)
          end
          input.each_with_index.map do |element, index|
            member.encode_unsafe(element)
          rescue CodecError => exception
            raise exception.with_path(index, :encode)
          end
        end

        # Build a lax type
        #
        # @return [Lax]
        #
        # @api public
        def lax = Lax.new(Member.new(primitive, **options, member: member.lax, meta: meta))

        # @see Nominal#to_ast
        #
        # @api public
        def to_ast(meta: true)
          if member.respond_to?(:to_ast)
            [:array, [member.to_ast(meta: meta), meta_ast(meta)]]
          else
            [:array, [member, meta_ast(meta)]]
          end
        end

        # @api private
        def constructor_type = ::Dry::Types::Array::Constructor

        private

        def externally_conforms?(type, value)
          case type
          when Codec then externally_conforms?(type.external, value)
          when Schema then type.conforms_without_codec?(value, :encode)
          when Array::Member then type.conforms_without_codec?(value, :encode)
          when Default then externally_conforms?(type.type, value)
          when Constrained then type.try(value).success?
          when Nominal then type.primitive?(value)
          else type.try(value).success?
          end
        end
      end
    end
  end
end
