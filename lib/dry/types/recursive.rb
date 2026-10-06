# frozen_string_literal: true

module Dry
  module Types
    # Named recursive type.
    #
    # @api public
    class Recursive
      # Lazy named reference used while building recursive types.
      #
      # @api public
      class Reference
        include Type
        include Builder
        include Options
        include Meta
        include Printable
        include ::Dry::Equalizer(:reference_name, :options, :meta, inspect: false, immutable: true)

        attr_reader :reference_name
        attr_reader :binding

        def self.bind(references, roots)
          references.each do |reference|
            reference.bind(roots.fetch(reference.reference_name))
          end
        end

        def initialize(reference_name, binding: Binding.new, meta: EMPTY_HASH, **options)
          @reference_name = reference_name
          @binding = binding
          super(meta: meta, **options)
        end

        def target
          return binding.target unless binding.target.nil?

          raise ::KeyError, "unresolved recursive type reference #{reference_name.inspect}"
        end

        alias_method :type, :target

        def call_unsafe(input)
          graph = GraphContext.current
          return target.call_unsafe(input) unless graph

          graph.resolve_reference(target, self, input, safe: false) { target.call_unsafe(input) }
        end

        def call_safe(input, &block)
          graph = GraphContext.current
          return target.call_safe(input, &block) unless graph

          graph.resolve_reference(target, self, input, safe: true) { target.call_safe(input, &block) }
        end

        def try(input, &)
          graph = GraphContext.current
          return target.try(input, &) unless graph

          graph.resolve_reference(target, self, input, safe: true) { target.try(input, &) }
        end

        def primitive?(value) = bound? ? target.primitive?(value) : false

        def default? = bound? ? target.default? : false

        def constrained? = bound? ? target.constrained? : false

        def optional? = bound? ? target.optional? : false

        def bound? = !binding.target.nil?

        def lax = bound? ? target.lax : self

        def to_ast(meta: true)
          [:reference, [reference_name, meta ? self.meta : EMPTY_HASH]]
        end

        def bind(new_target)
          binding.target = new_target
          self
        end

        def with(**new_options)
          if new_options.empty?
            self
          else
            self.class.new(
              reference_name,
              binding: binding,
              **options,
              **new_options.except(:meta),
              meta: @meta.merge(new_options.fetch(:meta, EMPTY_HASH))
            )
          end
        end

        def respond_to_missing?(name, include_private = false)
          bound? && target.respond_to?(name, include_private) || super
        end

        def name
          bound? ? target.name : "recursive_reference(#{reference_name.inspect})"
        end

        private

      end

      Binding = Class.new do
        attr_accessor :target

        def initialize(target = nil)
          @target = target
        end
      end


      include Type
      include Decorator
      include Builder
      include Printable
      include ::Dry::Equalizer(:type, :root, :names, :cycle_policy, :options, :meta, inspect: false, immutable: true)

      attr_reader :root
      attr_reader :names
      attr_reader :cycle_policy
      attr_reader :bindings

      def self.build(names, root = nil, on_cycle: :reject, &block)
        names = normalize_names(names)
        references = names.to_h { |name| [name, Recursive::Reference.new(name)] }

        body =
          if block
            block.call(*names.map { |name| references.fetch(name) })
          else
            references.fetch(root || names.first)
          end

        bodies = body.is_a?(::Hash) ? body : {(root || names.first) => body}
        unknown = bodies.keys - names
        raise ::ArgumentError, "unknown recursive roots: #{unknown.map(&:inspect).join(", ")}" unless unknown.empty?

        root_name = root || bodies.keys.first
        raise ::ArgumentError, "unknown recursive root #{root_name.inspect}" unless bodies.key?(root_name)

        roots = bodies.transform_values do |value|
          value.is_a?(self) ? value.type : value
        end
        Recursive::Reference.bind(references.values, roots)

        new(roots.fetch(root_name), root: root_name, names: names, on_cycle: on_cycle, bindings: roots)
      end

      def self.normalize_names(names)
        Array(names).flatten.map(&:to_sym).tap do |normalized|
          if normalized.empty?
            raise ::ArgumentError, "at least one recursive name is required"
          elsif normalized.uniq.length != normalized.length
            raise ::ArgumentError, "recursive names must be unique"
          end
        end
      end

      def initialize(
        type,
        root: nil,
        names: EMPTY_ARRAY,
        on_cycle: :reject,
        cycle_policy: nil,
        bindings: nil,
        **options
      )
        @root = root || (names.first if names.any?)
        @names = names
        @cycle_policy = GraphContext.coerce(cycle_policy || on_cycle)
        @bindings = bindings || EMPTY_HASH
        super
        @root ||= :type
        @names = [@root] if @names.empty?
        freeze
      end

      def call_unsafe(input)
        graph = GraphContext.current
        return type.call_unsafe(input) if graph

        GraphContext.new(cycle_policy).call(self, input) { type.call_unsafe(input) }
      end

      def call_safe(input, &block)
        graph = GraphContext.current
        return type.call_safe(input, &block) if graph

        GraphContext.new(cycle_policy).call(self, input) { type.call_safe(input, &block) }
      end

      def try(input, &)
        return type.try(input, &) if GraphContext.current

        GraphContext.new(cycle_policy).call(self, input) { type.try(input, &) }
      end

      def on_cycle(policy)
        self.class.new(type, **options, root: root, names: names, on_cycle: policy, bindings: bindings)
      end

      alias_method :cycle_policy=, :on_cycle

      def reject_cycles = on_cycle(:reject)

      def preserve_cycles = on_cycle(:preserve)

      def with(**new_options)
        if new_options.empty?
          self
        else
          next_policy = new_options.fetch(:on_cycle, new_options.fetch(:cycle_policy, @cycle_policy))
          self.class.new(
            type, **options, **new_options.except(:on_cycle, :cycle_policy),
            root: root, names: names, on_cycle: next_policy, bindings: bindings
          )
        end
      end

      def to_ast(meta: true)
        if names.one? && root == names.first
          [:recursive, [root, type.to_ast(meta: meta), cycle_policy, meta ? self.meta : EMPTY_HASH]]
        else
          [:recursive, [
            names.to_h { |name| [name, type_for(name).to_ast(meta: meta)] },
            root, cycle_policy, meta ? self.meta : EMPTY_HASH
          ]]
        end
      end

      def name = type.name

      private

      def type_for(name)
        return type if name == root

        bindings.fetch(name) do
          raise ::KeyError, "recursive name #{name.inspect} is not present in #{root.inspect}"
        end
      end
    end
  end
end
