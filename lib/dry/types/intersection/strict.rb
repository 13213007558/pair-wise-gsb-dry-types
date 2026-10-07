# frozen_string_literal: true

module Dry
  module Types
    class Intersection
      # Strict intersection evaluation
      #
      # @api private
      class Strict
        # @api private
        Evaluation = ::Data.define(:side, :result)

        # @api private
        Entry = ::Data.define(:merger, :check)

        Registry = ::Data.define(:mergers) do
          def self.empty = new({})

          def register(left, right, merger = nil, check: nil, &block)
            merger = Undefined.default(merger, block)
            raise ::ArgumentError, "a merger must be provided" unless merger.respond_to?(:call)

            store(left, right, Entry.new(merger, check))
            store(Strict.raw_type(left), Strict.raw_type(right), Entry.new(merger, check))

            self
          end

          def store(left, right, entry)
            mergers.store([left, right], entry)
            mergers.store([right, left], entry)
          end

          def [](left, right)
            mergers[[left, right]]
          end
        end

        class Error < CoercionError
          attr_reader :path, :left, :right, :stage, :cause_error

          def initialize(message, path:, left:, right:, stage:, cause_error: nil)
            super(message)
            @path = path
            @left = left
            @right = right
            @stage = stage
            @cause_error = cause_error
          end
        end

        class TypeValidationError < Error; end

        class MergeConflict < Error; end

        class UnsupportedCombination < Error
          def initialize(left, right, path: EMPTY_ARRAY, stage: :support)
            super(
              "strict intersection cannot verify #{Strict.path_to_s(path)}: " \
                "#{left.inspect} and #{right.inspect}",
              path: path,
              left: left,
              right: right,
              stage: stage
            )
          end
        end

        def self.registry
          @registry ||= Registry.empty
        end

        def self.register_merger(...) = registry.register(...)

        def self.path_to_s(path)
          return "$" if path.empty?

          path.map { |part|
            case part
            when ::Integer then "[#{part}]"
            when ::Symbol then ".#{part}"
            else "[#{part.inspect}]"
            end
          }.join.prepend("$")
        end

        def self.raw_type(type)
          case type
          when Types::Constructor then raw_type(type.type)
          when Types::Schema::Key then type
          when Decorator then raw_type(type.type)
          else type
          end
        end

        def self.supported_combination?(left, right)
          evaluator = new(nil, nil)
          evaluator.send(:combination_supported?, left, right)
        end

        def initialize(intersection, input)
          @intersection = intersection
          @input = input
        end

        def call
          left_result = evaluate(@intersection.left, :left)
          right_result = evaluate(@intersection.right, :right)
          failures = [left_result, right_result].select { _1.result.failure? }

          if failures.any?
            raise TypeValidationError.new(
              failures.map { _1.result.error.to_s }.join("; "),
              path: EMPTY_ARRAY,
              left: side_value(left_result),
              right: side_value(right_result),
              stage: :type_validation,
              cause_error: failures.first.result.error
            )
          end

          merged = merge(
            @intersection.left, left_result.result.input,
            @intersection.right, right_result.result.input,
            EMPTY_ARRAY
          )

          merged
        end

        private

        def evaluate(type, side)
          result = evaluation_node(type).call(@input)
          Evaluation.new(side, result)
        end

        def evaluation_node(type)
          case type
          when Types::Constructor
            inner = evaluation_node(type.type)
            ->(input) do
              begin
                coerced = type.fn.(input)
                inner.call(coerced)
              rescue StandardError => exception
                Result::Failure.new(input, CoercionError.new(exception.message))
              end
            end
          when Types::Constrained
            type_node = evaluation_node(type.type)
            ->(input) do
              result = type_node.call(input)
              rule_value = type.is_a?(Types::Constrained::Coercible) ? input : result.input
              if result.success? && type.rule[rule_value]
                result
              else
                result.success? ? failure_result(input, type) : result
              end
            end
          when Types::Schema
            ->(input) { evaluation_schema(type, input) }
          when Types::Array::Member
            ->(input) { evaluation_array_member(type, input) }
          when Intersection
            ->(input) do
              begin
                Result::Success.new(Strict.new(type, input).call)
              rescue Strict::Error => failure
                Result::Failure.new(input, failure)
              end
            end
          when Types::Schema::Key
            evaluation_node(type.type)
          when Types::Default
            ->(input) do
              if Undefined.equal?(input)
                Result::Success.new(type.evaluate)
              else
                evaluation_node(type.type).call(input)
              end
            end
          when Types::Enum
            inner = evaluation_node(type.type)
            ->(input) { inner.call(type.map_value(input)) }
          when Types::Lax
            evaluation_node(type.type)
          else
            ->(input) { type.try(input) }
          end
        end

        def evaluation_schema(type, input)
          return type.try(input) unless input.is_a?(::Hash)

          output = {}

          input.each do |key, value|
            normalized_key = type.transform_key.call(key)
            key_type = type.name_key_map[normalized_key]
            next unless key_type

            result = evaluation_node(key_type).call(value)
            if result.failure?
              output[normalized_key] = result.input
              return Result::Failure.new(output, result.error)
            end
            output[normalized_key] = result.input
          end

          type.keys.each do |key|
            next if output.key?(key.name) || !key.default?
            output[key.name] = key.call_unsafe(Undefined)
          end

          Result::Success.new(output)
        end

        def evaluation_array_member(type, input)
          return type.try(input) unless input.is_a?(::Array)

          output = []

          input.each do |item|
            result = evaluation_node(type.member).call(item)
            return result if result.failure?
            output << result.input
          end

          Result::Success.new(output)
        end

        def failure_result(input, _type)
          error = CoercionError.new("#{input.inspect} does not conform strict intersection side")
          Result::Failure.new(input, error)
        end

        def side_value(evaluation)
          evaluation.result.input
        end

        def merge(left_type, left, right_type, right, path)
          custom = custom_merger(left_type, right_type)

          if custom
            merged = custom.merger.call(left, right)
            validate(left_type, right_type, left, right, merged, path, custom)
            return merged
          end

          merged = case [left, right]
          in [::Array, ::Array]
            merge_arrays(left_type, left, right_type, right, path)
          in [::Hash, ::Hash]
            merge_hashes(left_type, left, right_type, right, path)
          else
            unless values_equal?(left, right)
              raise MergeConflict.new(
                "conflicting values at #{path_to_s(path)}",
                path: path,
                left: left,
                right: right,
                stage: :merge
              )
            end

            left
          end

          validate(left_type, right_type, left, right, merged, path)
          merged
        end

        def merge_arrays(left_type, left, right_type, right, path)
          unless left.length == right.length
            raise MergeConflict.new(
              "conflicting array lengths at #{path_to_s(path)}",
              path: path,
              left: left,
              right: right,
              stage: :merge
            )
          end

          left.each_index.map do |index|
            child_path = [*path, index]
            merge(
              array_member(left_type), left[index],
              array_member(right_type), right[index],
              child_path
            )
          end
        end

        def merge_hashes(left_type, left, right_type, right, path)
          keys = (left.keys + right.keys).uniq

          keys.each_with_object({}) do |key, merged|
            child_path = [*path, key]

            if left.key?(key) && right.key?(key)
              merged[key] = merge(
                hash_value_type(left_type, key), left[key],
                hash_value_type(right_type, key), right[key],
                child_path
              )
            elsif left.key?(key)
              merged[key] = left[key]
            else
              merged[key] = right[key]
            end
          end
        end

        def validate(left_type, right_type, left, right, value, path, custom = nil)
          if custom
            run_custom_check(custom, value, left, right, path)
          end

          unless validate_pure?(left_type, right_type, custom)
            raise UnsupportedCombination.new(left_type, right_type, path: path)
          end

          node = pure_pair_node(left_type, right_type, path)

          begin
            node.call(value)
          rescue UnsupportedCombination
            raise unless custom&.check
          rescue TypeValidationError, MergeConflict
            raise
          rescue StandardError => exception
            raise TypeValidationError.new(
              exception.message,
              path: path,
              left: left,
              right: right,
              stage: :type_validation,
              cause_error: exception
            )
          end
        end

        def validate_pure?(left_type, right_type, custom)
          return true if custom&.check

          [left_type, right_type].all? do |type|
            pure_node(type, EMPTY_ARRAY)
            true
          rescue UnsupportedCombination
            false
          end
        end

        def pure_pair_node(left_type, right_type, path)
          left = raw_type(left_type)
          right = raw_type(right_type)

          if (left_rule, left_inner = constrained_parts(left_type)) &&
             (right_rule, right_inner = constrained_parts(right_type)) &&
             left_inner.is_a?(Types::Schema) && right_inner.is_a?(Types::Schema)
            schema_node = pure_schema(merge_schemas(left_inner, right_inner), path)
            ->(value) do
              [left_rule, right_rule].each do |rule|
                result = rule.(value)
                raise ConstraintError.new(result, value) unless result.success?
              end
              schema_node.call(value)
            end
          elsif left.is_a?(Types::Schema) && right.is_a?(Types::Schema)
            pure_schema(merge_schemas(left, right), path)
          else
            left_node = pure_node(left_type, path)
            right_node = pure_node(right_type, path)
            ->(value) do
              left_node.call(value)
              right_node.call(value)
            end
          end
        end

        def merge_schemas(left, right)
          left.merge(right).strict(false)
        end

        def constrained_parts(type)
          unwrapped = type

          while unwrapped.is_a?(Types::Constrained)
            return [unwrapped.rule, raw_type(unwrapped.type)]
          end
        end

        def run_custom_check(custom, value, left, right, path)
          if custom.check
            begin
              result = custom.check.call(value)
            rescue StandardError => exception
              raise TypeValidationError.new(
                exception.message,
                path: path,
                left: left,
                right: right,
                stage: :custom_check,
                cause_error: exception
              )
            end

            if result == false
              raise TypeValidationError.new(
                "custom check failed at #{path_to_s(path)}",
                path: path,
                left: left,
                right: right,
                stage: :custom_check
              )
            end
          end
        end

        def pure_node(type, path)
          unwrapped = raw_type(type)

          case unwrapped
          when Intersection
            intersection_node(unwrapped, path)
          when Types::Constrained
            pure_constrained(unwrapped, path)
          when Types::Schema
            pure_schema(unwrapped, path)
          when Types::Array::Member
            pure_array_member(unwrapped, path)
          when Types::Map
            pure_map(unwrapped, path)
          when Types::Sum
            pure_sum(unwrapped, path)
          when Types::Schema::Key
            pure_node(unwrapped.type, path)
          when Types::Lax
            ->(_value) {}
          when Types::Default
            pure_default(unwrapped, path)
          when Types::Enum
            pure_enum(unwrapped, path)
          when Types::Nominal, AnyClass
            pure_nominal(unwrapped, path)
          else
            raise UnsupportedCombination.new(type, type, path: path)
          end
        end

        def pure_default(type, path)
          inner = pure_node(type.type, path)
          ->(value) { inner.call(value) }
        end

        def pure_enum(type, path)
          inner = pure_node(type.type, path)
          values = type.values
          ->(value) do
            inner.call(value)
            unless values.include?(value)
              raise CoercionError.new("#{value.inspect} is not a valid enum value")
            end
          end
        end

        def intersection_node(type, path)
          pure_pair_node(type.left, type.right, path)
        end

        def pure_constrained(type, path)
          inner = pure_node(type.type, path)
          rule = type.rule
          ->(value) do
            result = rule.(value)
            raise ConstraintError.new(result, value) unless result.success?
            inner.call(value)
          end
        end

        def pure_schema(type, path)
          keys = type.keys
          strict = type.strict?

          lambda do |value|
            unless value.is_a?(::Hash)
              raise CoercionError.new("#{value.inspect} must be a hash")
            end

            keys.each do |key|
              next unless value.key?(key.name)
              child_path = [*path, key.name]
              begin
                pure_node(key.type, child_path).call(value[key.name])
              rescue TypeValidationError, MergeConflict, UnsupportedCombination
                raise
              rescue StandardError => exception
                raise TypeValidationError.new(
                  exception.message,
                  path: child_path,
                  left: value[key.name],
                  right: value[key.name],
                  stage: :type_validation,
                  cause_error: exception
                )
              end
            end

            missing = keys.select { |key| key.required? && !value.key?(key.name) }
            if missing.any?
              child_path = [*path, missing.first.name]
              raise TypeValidationError.new(
                MissingKeyError.new(missing.first.name).message,
                path: child_path,
                left: value,
                right: value,
                stage: :type_validation
              )
            end

            if strict
              unknown = value.keys.map(&type.transform_key) - keys.map(&:name)
              if unknown.any?
                raise TypeValidationError.new(
                  UnknownKeysError.new(unknown).message,
                  path: path,
                  left: value,
                  right: value,
                  stage: :type_validation
                )
              end
            end
          end
        end

        def pure_array_member(type, path)
          member = pure_node(type.member, [*path, :*])
          ->(value) do
            unless value.is_a?(::Array)
              raise CoercionError.new("#{value.inspect} must be an array")
            end

            value.each_with_index do |item, index|
              child_path = [*path, index]
              begin
                member.call(item)
              rescue TypeValidationError, MergeConflict, UnsupportedCombination
                raise
              rescue StandardError => exception
                raise TypeValidationError.new(
                  exception.message,
                  path: child_path,
                  left: item,
                  right: item,
                  stage: :type_validation,
                  cause_error: exception
                )
              end
            end
          end
        end

        def pure_map(type, path)
          key_node = pure_node(type.key_type, [*path, :key])
          value_node = pure_node(type.value_type, [*path, :value])
          ->(value) do
            unless value.is_a?(::Hash)
              raise CoercionError.new("#{value.inspect} must be a hash")
            end

            value.each do |key, item|
              key_node.call(key)
              value_node.call(item)
            end
          end
        end

        def pure_sum(type, path)
          left = pure_node(type.left, path)
          right = pure_node(type.right, path)
          ->(value) do
            begin
              left.call(value)
            rescue StandardError
              right.call(value)
            end
          end
        end

        def pure_nominal(type, _path)
          primitive = type.primitive
          ->(value) do
            unless value.is_a?(primitive)
              raise CoercionError.new("#{value.inspect} must be an instance of #{primitive}")
            end
          end
        end

        def raw_type(type)
          case type
          when Types::Constructor then raw_type(type.type)
          when Types::Schema::Key then type
          when Decorator then raw_type(type.type)
          else type
          end
        end

        def custom_merger(left_type, right_type)
          Strict.registry[left_type, right_type] ||
            Strict.registry[raw_type(left_type), raw_type(right_type)]
        end

        def combination_supported?(left_type, right_type)
          custom = custom_merger(left_type, right_type)
          return true if custom&.check

          ![left_type, right_type].any? { wrapped_intersection?(_1) } &&
            [left_type, right_type].all? { type_supported?(_1) }
        end

        def wrapped_intersection?(type)
          case type
          when Intersection, Types::Constrained
            false
          when Types::Constructor, Decorator
            raw_type(type).is_a?(Intersection)
          else
            false
          end
        end

        def type_supported?(type)
          case type
          when Intersection
            type_supported?(type.left) && type_supported?(type.right)
          when Types::Schema
            type.keys.all? { |key| type_supported?(key.type) }
          when Types::Array::Member
            type_supported?(type.member)
          when Types::Map
            type_supported?(type.key_type) && type_supported?(type.value_type)
          when Types::Sum
            type_supported?(type.left) && type_supported?(type.right)
          when Types::Constrained, Types::Schema::Key, Types::Constructor,
               Types::Default, Types::Enum, Types::Lax, Decorator
            type_supported?(type.type)
          when Types::Nominal, AnyClass
            true
          else
            false
          end
        end

        def array_member(type)
          unwrapped = raw_type(type)
          unwrapped.is_a?(Types::Array::Member) ? unwrapped.member : Types["any"]
        end

        def hash_value_type(type, key)
          unwrapped = raw_type(type)

          case unwrapped
          when Types::Schema
            unwrapped.key?(key) ? unwrapped.key(key).type : Types["any"]
          when Types::Map
            unwrapped.value_type
          else
            Types["any"]
          end
        end

        def values_equal?(left, right) = left == right

        def path_to_s(path)
          return "$" if path.empty?

          path.map { |part|
            case part
            when ::Integer then "[#{part}]"
            when ::Symbol then ".#{part}"
            else "[#{part.inspect}]"
            end
          }.join.prepend("$")
        end

      end
    end
  end
end
