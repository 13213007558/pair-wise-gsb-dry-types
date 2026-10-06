# frozen_string_literal: true

module Dry
  module Types
    class Recursion
      REJECT = :reject
      KEEP = :keep
      STRATEGIES = [REJECT, KEEP].freeze

      class Transaction
        attr_reader :keys

        def initialize
          @keys = []
        end

        def record(key)
          @keys << key unless @keys.include?(key)
        end

        def rollback(entries, rejected_inputs)
          @keys.each do |key|
            entry = entries[key]
            next if entry.nil?
            next if rejected_inputs.include?(key)
            next unless entry[:owner].equal?(self)

            entries.delete(key)
          end
        end

        def merge!(other)
          other.keys.each { |key| record(key) }
        end
      end

      class NullTransaction
        def rollback(_entries, _rejected_inputs)
        end
      end

      NULL_TRANSACTION = NullTransaction.new

      def self.validate_strategy(strategy)
        return strategy if STRATEGIES.include?(strategy)

        raise ::ArgumentError,
              "unknown recursion strategy #{strategy.inspect}; " \
              "supported strategies are #{STRATEGIES.map(&:inspect).join(", ")}"
      end

      def self.stack
        Thread.current[:dry_types_recursion] ||= []
      end

      def self.current
        stack.last
      end

      def self.run(strategy, root_name)
        state = new(validate_strategy(strategy))
        stack.push(state)

        begin
          state.reference(root_name, nil, nil) { yield }
        ensure
          stack.pop
        end
      end

      def self.run_lax(strategy, root_name)
        @lax_depth = @lax_depth.to_i + 1
        run(strategy, root_name) { yield }
      ensure
        @lax_depth = @lax_depth.to_i - 1
      end

      def self.lax?
        @lax_depth.to_i.positive?
      end

      def self.apply(target, input, name = nil)
        state = current
        if state.nil?
          return yield(target.is_a?(Composition) ? nil : inactive_seed(target))
        end

        rejected = state.rejected[input]
        raise rejected unless rejected.nil?

        state.apply(target, input, name) { |output| yield(output) }
      rescue ::Dry::Types::CircularReferenceError => exception
        state.mark_rejected(input, exception)
        raise
      end

      def self.reference(name, target, input)
        state = current

        if state.nil?
          raise RecursiveReferenceError,
                "recursive reference :#{name} is not bound to a recursive root"
        end

        state.reference(name, target, input) { yield }
      end

      def self.transaction
        state = current
        return yield(NULL_TRANSACTION) if state.nil?

        state.transaction { |transaction| yield(transaction) }
      end

      def self.keep?
        current&.keep?
      end

      def self.rollback_transaction(transaction)
        state = current
        transaction.rollback(
          state&.entries || {},
          state&.rejected&.keys || []
        )
      end

      def self.inactive_seed(target)
        if target.is_a?(Schema)
          {}
        elsif target.is_a?(Array::Member)
          []
        end
      end

      attr_reader :strategy, :entries, :rejected, :transactions, :names

      def initialize(strategy)
        @strategy = self.class.validate_strategy(strategy)
        @entries = {}
        @rejected = {}
        @transactions = []
        @names = []
      end

      def keep?
        strategy == KEEP
      end

      def reference(name, _target, _input)
        names.push(name)
        yield
      ensure
        names.pop
      end

      def apply(target, input, name = nil)
        entry_key = input
        status_key = target
        entry = entries[entry_key]
        status = entry&.dig(:statuses, status_key)

        if status
          target_output = entry[:outputs][status_key]
          return target_output if status == :completed
          raise entry[:rejected] if status == :rejected

          if keep?
            return target_output
          else
            raise Types::CircularReferenceError.new(name || names.last, input)
          end
        end

        owner = transactions.last
        created_entry = entry.nil?
        output = seed_for(target, input)

        entry ||= {
          output: output,
          outputs: {},
          statuses: {},
          owner: owner,
          rejected: nil
        }
        entry[:statuses][status_key] = :progress
        entry[:outputs][status_key] = output
        entries[entry_key] = entry
        record(entry_key) if created_entry || entry[:owner].equal?(owner)

        begin
          actual_output = yield(output)
          entry[:statuses][status_key] = :completed
          if actual_output.is_a?(::Dry::Types::Result)
            entry[:output] = actual_output.input if actual_output.success?
            actual_output
          elsif target.is_a?(Composition) && seed_container?(output)
            entry[:output] = actual_output
            actual_output
          else
            output
          end
        rescue StandardError => exception
          if exception.is_a?(::Dry::Types::CircularReferenceError)
            entry[:rejected] = exception
            @rejected[entry_key] = exception
          end

          entry[:statuses].delete(status_key)
          if entry[:statuses].empty? && entry[:owner].equal?(owner) &&
             !@rejected.key?(entry_key)
            entries.delete(entry_key)
          end
          raise
        end
      end

      def transaction
        transaction = Transaction.new
        transactions.push(transaction)
        yield(transaction)
      ensure
        if transactions.last.equal?(transaction)
          transactions.pop
          transactions.last&.merge!(transaction)
        end
      end

      def mark_rejected(input, exception)
        @rejected[input] = exception
        entry = entries[input]
        entry[:rejected] = exception unless entry.nil?
      end

      private

      def record(key)
        transactions.last&.record(key)
      end

      def seed_for(target, input)
        case target
        when Composition
          seed_for_composition(target, input)
        when Schema
          {}
        when Array::Member
          []
        else
          input
        end
      end

      def seed_for_composition(type, input)
        seed = composition_seed(type.left, input)
        seed.nil? ? composition_seed(type.right, input) : seed
      end

      def composition_seed(type, input)
        case type
        when Composition
          seed_for_composition(type, input)
        when Schema
          {} if input.is_a?(::Hash)
        when Array::Member
          [] if input.is_a?(::Array)
        end
      end

      def seed_container?(value)
        value.is_a?(::Hash) || value.is_a?(::Array)
      end
    end
  end
end
