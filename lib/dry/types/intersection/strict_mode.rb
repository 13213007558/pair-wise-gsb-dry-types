# frozen_string_literal: true

module Dry
  module Types
    class Intersection
      # Side-effect-free support for strict intersection types.
      #
      # @api private
      module StrictMode
        module_function

        def validator(type)
          structure = pure_structure(type)

          if structure.is_a?(BothValidator)
            structure
          else
            PureValidator.new(structure)
          end
        end

        def merge(left_result, right_result, left:, right:, registry:, intersection: nil,
                  path: EMPTY_ARRAY)
          if path.empty?
            custom = registry.lookup(left, right)

            if custom
              merger, checker = custom
              merged =
                if merger.arity == 3
                  merger.call(left_result, right_result, intersection)
                else
                  merger.call(left_result, right_result)
                end

              unless checker.nil? || checker.call(merged)
                raise IntersectionConflictError.new(
                  path, left_result, right_result, :custom_checker
                )
              end

              return merged
            end
          end

          structural_merge(
            left_result, right_result,
            path: path
          )
        end

        # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/MethodLength, Metrics/PerceivedComplexity
        def pure_structure(type)
          case type
          when Intersection
            BothValidator.new(validator(type.left), validator(type.right))
          when ::Dry::Types::Constrained::Coercible
            ::Dry::Types::Constrained.new(
              primitive_structure(type.type), rule: type.rule
            )
          when Lax
            raise_intersection_unverifiable(type, "lax types do not expose strict constraints")
          when Constructor
            primitive_structure(type.type)
          when ::Dry::Types::Constrained
            ::Dry::Types::Constrained.new(pure_structure(type.type), rule: type.rule)
          when Schema::Key
            Schema::Key.new(
              pure_structure(type.type), type.name, required: type.required?
            )
          when Schema
            Schema.new(
              type.primitive,
              keys: type.keys.map { pure_structure(_1) },
              **type.options.slice(:strict)
            )
          when Map
            Map.new(
              type.primitive,
              key_type: pure_structure(type.key_type),
              value_type: pure_structure(type.value_type)
            )
          when Array::Member
            Array::Member.new(
              type.primitive, member: pure_structure(type.member)
            )
          when Enum
            pure_structure(type.type)
          when Sum
            pure_structure(type.left) | pure_structure(type.right)
          when Default
            pure_structure(type.type)
          when AnyClass
            AnyClass.new
          when ::Dry::Types::Nominal
            type.class.new(type.primitive)
          else
            raise_intersection_unverifiable(
              type, "its result cannot be checked without invoking a constructor"
            )
          end
        end
        # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity
        # rubocop:enable Metrics/MethodLength, Metrics/PerceivedComplexity

        def structural_merge(left_result, right_result, path:) # rubocop:disable Metrics/MethodLength
          case [left_result, right_result]
          in [::Array, ::Array]
            unless left_result.length == right_result.length
              raise IntersectionConflictError.new(
                path, left_result, right_result, :array_length
              )
            end

            left_result.zip(right_result).map.with_index do |(item_left, item_right), index|
              structural_merge(
                item_left, item_right,
                path: path + [index]
              )
            end
          in [::Hash, ::Hash]
            (left_result.keys | right_result.keys).each_with_object({}) do |key, merged|
              if left_result.key?(key) && right_result.key?(key)
                merged[key] = structural_merge(
                  left_result.fetch(key), right_result.fetch(key),
                  path: path + [key]
                )
              else
                merged[key] = left_result.key?(key) ? left_result.fetch(key) : right_result.fetch(key)
              end
            end
          else
            unless left_result.eql?(right_result)
              raise IntersectionConflictError.new(path, left_result, right_result)
            end

            left_result
          end
        end

        def raise_intersection_unverifiable(type, reason)
          raise IntersectionUnverifiableError.new(type, reason)
        end

        def primitive_structure(type)
          structure = pure_structure(type)

          if structure.is_a?(::Dry::Types::Nominal) && structure.primitive != ::Object
            structure.constrained(type: structure.primitive)
          else
            structure
          end
        end

        class PureValidator # rubocop:disable Metrics/ClassLength
          attr_reader :type

          def initialize(type)
            @type = type
            freeze
          end

          def validate(value, path, left_result, right_result)
            validate_type(type, value, path, left_result, right_result)
            value
          end

          private

          # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
          # rubocop:disable Metrics/MethodLength, Metrics/PerceivedComplexity
          def validate_type(type, value, path, left_result, right_result)
            case type
            when BothValidator
              type.validate(value, path, left_result, right_result)
            when Schema
              unless value.is_a?(::Hash)
                assert_type(type, value, path, left_result, right_result)
              end

              value.each do |key, item|
                key_type = type.key(key, nil)
                validate_type(key_type.type, item, path + [key], left_result, right_result) if key_type
              end
            when Map
              assert_type(type, value, path, left_result, right_result)
              value.each do |key, item|
                validate_type(type.key_type, key, path + [key], left_result, right_result)
                validate_type(type.value_type, item, path + [key], left_result, right_result)
              end
            when Array::Member
              assert_type(type, value, path, left_result, right_result)
              value.each_with_index do |item, index|
                validate_type(type.member, item, path + [index], left_result, right_result)
              end
            when ::Dry::Types::Constrained
              assert_type(type, value, path, left_result, right_result)
              validate_type(type.type, value, path, left_result, right_result)
            when Schema::Key
              validate_type(type.type, value, path, left_result, right_result)
            when Sum
              assert_type(type, value, path, left_result, right_result)
              branch = type.left.try(value).success? ? type.left : type.right
              validate_type(branch, value, path, left_result, right_result)
            else
              assert_type(type, value, path, left_result, right_result)
            end
          end
          # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity
          # rubocop:enable Metrics/MethodLength, Metrics/PerceivedComplexity

          def assert_type(type, value, path, left_result, right_result)
            result = type.try(value)
            return if result.success?

            raise IntersectionValidationError.new(
              path, left_result, right_result, result.error
            )
          end
        end

        class BothValidator
          attr_reader :left, :right

          def initialize(left, right)
            @left = left
            @right = right
            freeze
          end

          def validate(value, path, left_result, right_result)
            left.validate(value, path, left_result, right_result)
            right.validate(value, path, left_result, right_result)
            value
          end
        end
      end
    end
  end
end
