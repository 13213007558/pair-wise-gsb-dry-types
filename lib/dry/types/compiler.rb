# frozen_string_literal: true

module Dry
  module Types
    # @api private
    class Compiler
      extend ::Dry::Core::Deprecations[:"dry-types"]

      attr_reader :registry

      def initialize(registry)
        @registry = registry
        @recursion_scopes = []
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
        names, root, policy, meta = expand_recursive_node(node)
        references = names.each_with_object({}) do |(name, ast), result|
          result[name] = [ast, Types::Recursive::Reference.new(name)]
        end

        @recursion_scopes.push(references.transform_values { |_ast, reference| reference })
        begin
          bodies = references.transform_values { |ast, _reference| visit(ast) }
        ensure
          @recursion_scopes.pop
        end

        root_name = root || bodies.keys.first
        raise ::ArgumentError, "unknown recursive root #{root_name.inspect}" unless bodies.key?(root_name)

        Types::Recursive::Reference.bind(references.values.map(&:last), bodies)
        Types::Recursive.new(
          bodies.fetch(root_name),
          root: root_name,
          names: bodies.keys,
          on_cycle: policy,
          bindings: bodies
        ).meta(meta)
      end
      alias_method :visit_recursion, :visit_recursive

      def visit_reference(node)
        name, meta = node
        scope = @recursion_scopes.reverse.find { |bindings| bindings.key?(name) }

        if scope.nil?
          raise ::KeyError, "unresolved recursive type reference #{name.inspect}"
        end

        scope.fetch(name).meta(meta)
      end
      alias_method :visit_ref, :visit_reference

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

      private

      def expand_recursive_node(node)
        case node[0]
        when ::Hash
          [node[0], node[1], node.fetch(2, :reject), node.fetch(3, EMPTY_HASH)]
        else
          name = node[0]
          [{name => node[1]}, name, node.fetch(2, :reject), node.fetch(3, EMPTY_HASH)]
        end
      end
    end
  end
end
