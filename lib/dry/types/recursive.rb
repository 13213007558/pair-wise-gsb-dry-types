# frozen_string_literal: true

module Dry
  module Types
    class Recursive
      include Type
      include Decorator
      include Meta
      include Builder
      include Printable

      attr_reader :name, :definitions, :cycles

      def self.build(
        name = Undefined,
        type = Undefined,
        definitions: EMPTY_HASH,
        cycles: Recursion::REJECT,
        keep: nil,
        &block
      )
        strategy = keep.nil? ? cycles : (keep ? Recursion::KEEP : Recursion::REJECT)
        built_definitions = definitions.transform_keys(&:to_sym)

        if block
          references = {}
          reference_factory = proc do |reference_name|
            references[reference_name.to_sym] ||= Reference.new(reference_name.to_sym)
          end
          result =
            if block.arity.zero?
              ReferenceFactory.new(&reference_factory).instance_exec(&block)
            else
              block.call(reference_factory)
            end

          if result.is_a?(::Hash)
            built_definitions = result.transform_keys(&:to_sym)
          else
            type = result
          end
        end

        type = built_definitions.fetch(name.to_sym) if Undefined.equal?(type)

        new(
          type,
          name: name,
          definitions: built_definitions,
          cycles: strategy
        )
      end

      def self.ref(name)
        Reference.new(name)
      end

      def self.lazy(name)
        Reference.new(name)
      end

      def initialize(
        type,
        name:,
        definitions: EMPTY_HASH,
        cycles: Recursion::REJECT,
        keep: nil,
        **options
      )
        strategy = keep.nil? ? cycles : (keep ? Recursion::KEEP : Recursion::REJECT)
        @name = name.to_sym
        @cycles = Recursion.validate_strategy(strategy)
        @definitions = definitions.transform_keys(&:to_sym)

        super(type, **options)
        bind_references!
      end

      def call_unsafe(input)
        Recursion.run(cycles, name) { type.call_unsafe(input) }
      end

      def call_safe(input, &block)
        Recursion.run(cycles, name) do
          type.call_unsafe(input)
        rescue CoercionError
          yield(input)
        end
      end

      def try(input, &block)
        Recursion.run(cycles, name) do
          type.try(input, &block)
        rescue RecursiveReferenceError => exception
          failure = Result::Failure.new(input, exception)
          block ? yield(failure) : failure
        end
      end

      def call_lax(input)
        Recursion.run_lax(cycles, name) do
          type.call_unsafe(input)
        rescue CoercionError
          input
        end
      end

      def with(**new_options)
        return self if new_options.empty?

        self.class.new(
          type,
          name: name,
          definitions: definitions,
          cycles: cycles,
          **options,
          meta: meta,
          **new_options
        )
      end

      def to_ast(meta: true)
        definition_ast =
          definitions.transform_values { |definition| definition.to_ast(meta: meta) }

        [
          :recursive,
          [
            name,
            type.to_ast(meta: meta),
            {cycles: cycles, definitions: definition_ast},
            meta_ast(meta)
          ]
        ]
      end

      def lax
        Lax.new(self.class.new(
          type,
          name: name,
          definitions: definitions,
          cycles: cycles
        ))
      end

      class Reference
        include Type
        include Options
        include Meta
        include Builder
        include Printable

        attr_reader :name, :target

        def initialize(name, **options)
          @name = name.to_sym
          @target = nil
          super(**options)
        end

        def bind(target)
          @target = target if @target.nil?
          self
        end

        def bound?
          !target.nil?
        end

        def constrained?
          false
        end

        def default?
          false
        end

        def optional?
          false
        end

        def call_unsafe(input)
          ensure_bound!
          recurse(input) { target.call_unsafe(input) }
        end

        def call_safe(input, &block)
          ensure_bound!
          recurse(input) { target.call_safe(input, &block) }
        end

        def try(input, &block)
          ensure_bound!
          recurse(input) do
            target.try(input, &block)
          rescue RecursiveReferenceError => exception
            failure = Result::Failure.new(input, exception)
            block ? yield(failure) : failure
          end
        end

        def primitive?(value)
          ensure_bound!
          target.primitive?(value)
        end

        def to_ast(meta: true)
          [:recursive_ref, [name, meta_ast(meta)]]
        end

        private

        def ensure_bound!
          return if bound?

          raise RecursiveReferenceError,
                "recursive reference :#{name} is not bound"
        end

        def recurse(input)
          Recursion.reference(name, target, input) do
            if target.is_a?(Composition)
              Recursion.apply(target, input, name) { yield }
            else
              yield
            end
          end
        end

        def meta_ast(meta)
          meta ? self.meta : EMPTY_HASH
        end
      end

      class ReferenceFactory
        def initialize(&reference_factory)
          @reference_factory = reference_factory
        end

        private

        def method_missing(name, ...)
          @reference_factory.call(name)
        end

        def respond_to_missing?(*, **)
          true
        end
      end

      private

      def meta_ast(meta)
        meta ? self.meta : EMPTY_HASH
      end

      def bind_references!
        references = collect_references([type, *definitions.values])

        references.each do |reference_name, refs|
          target = definitions[reference_name] || (type if reference_name == name)
          next if target.nil?

          refs.each do |ref|
            ref.bind(target) unless ref.bound?
          end
        end
      end

      def collect_references(types)
        references = ::Hash.new { |hash, key| hash[key] = [] }
        visited = {}
        queue = types.dup

        until queue.empty?
          type = queue.shift
          next if type.nil? || visited.key?(type.object_id)

          visited[type.object_id] = true

          if type.is_a?(Reference)
            unless references[type.name].include?(type)
              references[type.name] << type
            end
            next
          end

          queue.concat(reference_children(type))
        end

        references
      end

      def reference_children(type)
        children = []

        case type
        when Schema
          children.concat(type.keys)
        when Schema::Key
          children << type.type
        when Array::Member
          children << type.member
        when Map
          children << type.key_type << type.value_type
        when Composition
          children << type.left << type.right
        when Decorator
          children << type.type
        when Enum
          children << type.type
        end

        children.select { |child| child.is_a?(Type) }
      end
    end
  end
end
