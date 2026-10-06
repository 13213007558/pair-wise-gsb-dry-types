# frozen_string_literal: true

module Dry
  module Types
    # @api private
    class GraphContext
      POLICIES = %i[reject preserve].freeze
      FIBER_KEY = :__dry_types_graph_context__

      attr_reader :policy

      def self.current
        ::Thread.current[FIBER_KEY]
      end

      def self.coerce(policy)
        policy = policy.to_sym
        raise ::ArgumentError, "unsupported cycle policy #{policy.inspect}" unless POLICIES.include?(policy)

        policy
      end

      def initialize(policy)
        @policy = self.class.coerce(policy)
        @values = {}
        @objects = {}
        @placeholders = {}
        @path = {}
        @pending = {}
        @pending_depth = {}
      end

      def call(type, input)
        previous = ::Thread.current[FIBER_KEY]
        ::Thread.current[FIBER_KEY] = self
        yield
      ensure
        ::Thread.current[FIBER_KEY] = previous
      end

      def resolve(type, input, safe:)
        id = identity(input)
        key = [id, type.object_id]
        return @values[key] if @values.key?(key)

        if @path.key?(id)
          raise RecursiveValueError.new(input) if policy == :reject

          return @placeholders.fetch(id)
        end

        yield
      end

      def resolve_reference(type, reference, input, safe:)
        id = identity(input)
        key = [id, type.object_id]
        return @values[key] if @values.key?(key)
        return @objects[id] if @objects.key?(id) && !@path.key?(id) && !@pending.key?(id)

        if @path.key?(id)
          raise RecursiveValueError.new(input) if policy == :reject

          return @placeholders.fetch(id)
        end

        depth = (@pending_depth[id] || 0) + 1
        @pending[id] = true
        @pending_depth[id] = depth
        yield
      ensure
        next_depth = (@pending_depth[id] || 1) - 1
        if next_depth.zero?
          @pending.delete(id)
          @pending_depth.delete(id)
        else
          @pending_depth[id] = next_depth
        end
      end

      def begin(input, output)
        id = identity(input)
        @placeholders[id] = output if preserve?
        @path[id] = (@path[id] || 0) + 1
      end

      def commit(type, input, output)
        id = identity(input)
        @values[[id, type.object_id]] = output
        @objects[id] = output unless @pending.key?(id)
      end

      def finish(input)
        id = identity(input)
        depth = (@path[id] || 1) - 1

        if depth.zero?
          @path.delete(id)
          @placeholders.delete(id)
        else
          @path[id] = depth
        end
      end

      def preserve? = policy.equal?(:preserve)

      private

      def identity(value)
        value.object_id
      end
    end
  end
end
