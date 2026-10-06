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
            Recursion.apply(self, input) do |output|
              input.each do |el|
                coerced =
                  if Types::Recursion.lax?
                    member.call_safe(el) { |out = el| out }
                  else
                    member.call_unsafe(el)
                  end

                output << coerced unless Undefined.equal?(coerced)
              end
              output
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

            result = Recursion.apply(self, input) do |output|
              input.each do |el|
                coerced = member.call_safe(el) { |out = el|
                  failed = true
                  out
                }

                output << coerced unless Undefined.equal?(coerced)
              end
              output
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
            Recursion.apply(self, input) do |recursive_output|
              array_result = begin
                result = input.map { |el| member.try(el) }
                recursive_failure = result.find do |r|
                  r.is_a?(::Dry::Types::Result::Failure) &&
                    r.error.is_a?(::Dry::Types::RecursiveReferenceError)
                end

                if recursive_failure
                  failure(recursive_output, recursive_failure.error)
                else
                  result.each do |r|
                    recursive_output << r.input unless Undefined.equal?(r.input)
                  end

                  if result.all?(&:success?)
                    success(recursive_output)
                  else
                    error = result.find(&:failure?).error
                    failure(recursive_output, error)
                  end
                end
              rescue ::Dry::Types::CircularReferenceError => exception
                failure(recursive_output, exception)
              end

              block ? yield(array_result) : array_result
            end
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
      end
    end
  end
end
