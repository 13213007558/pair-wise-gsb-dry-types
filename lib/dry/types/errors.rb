# frozen_string_literal: true

module Dry
  module Types
    extend ::Dry::Core::ClassAttributes

    # @!attribute [r] namespace
    #   @return [Container{String => Nominal}]
    defines :namespace

    namespace self

    # Base class for coercion errors raise by dry-types
    #
    class CoercionError < ::StandardError
      # @api private
      def self.handle(exception, meta: Undefined)
        if block_given?
          yield
        else
          raise new(
            exception.message,
            meta: meta,
            backtrace: exception.backtrace
          )
        end
      end

      # Metadata associated with the error
      #
      # @return [Object]
      attr_reader :meta

      # @api private
      def initialize(message, meta: Undefined, backtrace: Undefined)
        unless message.is_a?(::String)
          raise ::ArgumentError, "message must be a string, #{message.class} given"
        end

        super(message)
        @meta = Undefined.default(meta, nil)
        set_backtrace(backtrace) unless Undefined.equal?(backtrace)
      end
    end

    # Collection of multiple errors
    #
    class MultipleError < CoercionError
      # @return [Array<CoercionError>]
      attr_reader :errors

      # @param [Array<CoercionError>] errors
      def initialize(errors)
        super("")
        @errors = errors
      end

      # @return string
      def message = errors.map(&:message).join(", ")

      # @return [Array]
      def meta = errors.map(&:meta)
    end

    class SchemaError < CoercionError
      # @return [String, Symbol]
      attr_reader :key

      # @return [Object]
      attr_reader :value

      # @param [String,Symbol] key
      # @param [Object] value
      # @param [String, #to_s] result
      def initialize(key, value, result)
        @key = key
        @value = value
        super(
          "#{value.inspect} (#{value.class}) has invalid type " \
          "for :#{key} violates constraints (#{result} failed)"
        )
      end
    end

    MapError = ::Class.new(CoercionError)

    SchemaKeyError = ::Class.new(CoercionError)
    private_constant(:SchemaKeyError)

    class MissingKeyError < SchemaKeyError
      # @return [Symbol]
      attr_reader :key

      # @param [String,Symbol] key
      def initialize(key)
        @key = key
        super("#{key.inspect} is missing in Hash input")
      end
    end

    class UnknownKeysError < SchemaKeyError
      # @return [Array<Symbol>]
      attr_reader :keys

      # @param [<String, Symbol>] keys
      def initialize(keys)
        @keys = keys
        super("unexpected keys #{keys.inspect} in Hash input")
      end
    end

    class ConstraintError < CoercionError
      # @return [String, #to_s]
      attr_reader :result
      # @return [Object]
      attr_reader :input

      # @param [String, #to_s] result
      # @param [Object] input
      def initialize(result, input)
        @result = result
        @input = input

        if result.is_a?(::String)
          super(result)
        else
          super(to_s)
        end
      end

      # @return [String]
      def message
        "#{input.inspect} violates constraints (#{result} failed)"
      end
      alias_method :to_s, :message
    end

    # Error raised when a {Codec} fails to decode an external representation
    # or to encode an internal value
    #
    # The error carries the direction of the failed transformation and the
    # path to the failing value within nested structures
    #
    class CodecError < CoercionError
      # @return [:decode, :encode] direction of the failed transformation
      attr_reader :direction

      # @return [Array<Symbol, Integer>] path to the failing value,
      #   ordered from the outermost to the innermost segment
      attr_reader :path

      # @param [String] message
      # @param [:decode, :encode] direction
      # @param [Array<Symbol, Integer>] path
      def initialize(message, direction:, path: [], meta: Undefined, backtrace: Undefined)
        @direction = direction
        @path = path
        super(message, meta: meta, backtrace: backtrace)
      end

      # Prepend a path segment. Container types (arrays, schemas) use this
      # when re-raising errors coming from their members
      #
      # @param [Symbol, Integer] segment
      #
      # @return [CodecError] self
      #
      # @api private
      def prepend(segment)
        @path = [segment, *path]
        self
      end

      # @return [String]
      def message
        "#{direction} failed at #{location}: #{super}"
      end

      private

      # @return [String]
      #
      # @api private
      def location
        path.reduce("$".dup) do |location, segment|
          location << (segment.is_a?(::Integer) ? "[#{segment}]" : ".#{segment}")
        end
      end
    end

    # Raised when encoding a value through a sum type and more than one
    # branch accepts it. Tag the branches (see Builder#tagged) and provide
    # the tag in the value to disambiguate
    #
    class AmbiguousEncodingError < CodecError
      # @param [Object] input
      # @param [Array<Type>] branches accepting branches
      def initialize(input, branches)
        super(
          "#{input.inspect} is accepted by #{branches.size} branches of the sum type, " +
            "tag the branches and the value to disambiguate",
          direction: :encode
        )
      end
    end
  end
end
