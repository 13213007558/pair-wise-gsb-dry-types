# frozen_string_literal: true

module Dry
  module Types
    # @api private
    class Compiler
      extend ::Dry::Core::Deprecations[:"dry-types"]

      attr_reader :registry

      def initialize(registry)
        @registry = registry
        @recursive_scopes = []
      end

      def call(ast) = visit(ast)

      def visit(node)
        type, body = node
        send(:"visit_#{type}", body)
      end

      def visit_constrained(node)
        nominal, rule = node
        type = visit(nominal)
        type.constrained_type.new(type, rule: visit_rule(rule))
      end

      def visit_constructor(node)
        nominal, fn = node
        primitive = visit(nominal)
        primitive.constructor(compile_fn(fn))
      end

      def visit_lax(node)
        Types::Lax.new(visit(node))
      end
      deprecate(:visit_safe, :visit_lax)

      def visit_nominal(node)
        type, options, meta =
          case node
          in [type, options, meta]
            node
          in [type, meta]
            [type, EMPTY_HASH, meta]
          end

        nominal_name = "nominal.#{Types.identifier(type)}"

        if registry.registered?(nominal_name)
          registry[nominal_name].with(**options).meta(meta)
        else
          Nominal.new(type, meta: meta, **options)
        end
      end

      def visit_rule(node)
        ::Dry::Types.rule_compiler.([node])[0]
      end

      def visit_sum(node)
        *types, meta = node
        types.map { |type| visit(type) }.reduce(:|).meta(meta)
      end

      def visit_array(node)
        member, meta = node
        member = visit(member) unless member.is_a?(::Class)
        registry["nominal.array"].of(member).meta(meta)
      end

      def visit_hash(node)
        opts, meta = node
        registry["nominal.hash"].with(**opts, meta: meta)
      end

      def visit_schema(node)
        keys, options, meta = node
        registry["nominal.hash"].schema(keys.map { |key| visit(key) }).with(**options, meta: meta)
      end

      def visit_json_hash(node)
        keys, meta = node
        registry["json.hash"].schema(keys.map { |key| visit(key) }, meta)
      end

      def visit_json_array(node)
        member, meta = node
        registry["json.array"].of(visit(member)).meta(meta)
      end

      def visit_params_hash(node)
        keys, meta = node
        registry["params.hash"].schema(keys.map { |key| visit(key) }, meta)
      end

      def visit_params_array(node)
        member, meta = node
        registry["params.array"].of(visit(member)).meta(meta)
      end

      def visit_key(node)
        name, required, type = node
        Schema::Key.new(visit(type), name, required: required)
      end

      def visit_enum(node)
        type, mapping = node
        Enum.new(visit(type), mapping: mapping)
      end

      def visit_map(node)
        key_type, value_type, meta = node
        registry["nominal.hash"].map(visit(key_type), visit(value_type)).meta(meta)
      end

      def visit_any(meta)
        registry["any"].meta(meta)
      end

      def visit_recursive(node)
        name, root, options, meta = node
        name = name.to_sym
        definitions = options.fetch(:definitions, EMPTY_HASH)
        cycles = options.fetch(:cycles, Recursion::REJECT)
        scope = {refs: {}}

        @recursive_scopes.push(scope)

        begin
          compiled_definitions =
            definitions
              .transform_values { |definition| visit(definition) }
              .tap do |compiled|
                next if compiled.key?(name)

                compiled[name] = visit(root)
              end

          target = compiled_definitions.fetch(name)

          scope[:refs].each do |reference_name, reference|
            bound_target = compiled_definitions.fetch(reference_name) do
              raise RecursiveReferenceError,
                    "recursive reference :#{reference_name} is not defined"
            end

            reference.bind(bound_target)
          end
        ensure
          @recursive_scopes.pop
        end

        Recursive.new(
          target,
          name: name,
          definitions: compiled_definitions,
          cycles: Recursion.validate_strategy(cycles)
        ).meta(meta)
      end

      def visit_recursive_ref(node)
        name, _meta = node
        scope = @recursive_scopes.last

        if scope.nil?
          raise RecursiveReferenceError,
                "recursive reference :#{name} is outside of a recursive type"
        end

        scope[:refs][name.to_sym] ||= Recursive::Reference.new(name.to_sym)
      end

      def compile_fn(fn)
        type, *node = fn

        case type
        when :id
          ::Dry::Types::FnContainer[node.fetch(0)]
        when :callable
          node.fetch(0)
        when :method
          target, method = node
          target.method(method)
        else
          raise ::ArgumentError, "Cannot build callable from #{fn.inspect}"
        end
      end
    end
  end
end
