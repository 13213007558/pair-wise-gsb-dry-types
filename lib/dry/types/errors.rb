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

    # Raised when a codec cannot decode or encode a value
    #
    class CodecError < CoercionError
      # @return [Array<Symbol, Integer, String>]
      attr_reader :path

      # @return [Symbol]
      attr_reader :direction

      # @return [String]
      attr_reader :base_message

      # @api private
      def self.build(message, path: EMPTY_ARRAY, direction: nil, meta: Undefined)
        new(message, path: path, direction: direction, meta: meta)
      end

      # @api private
      def initialize(message, path: EMPTY_ARRAY, direction: nil, **options)
        @path = path
        @direction = direction
        @base_message = message
        super("#{direction_label}#{path_label}#{message}", **options)
      end

      # @api private
      def with_path(prefix, direction = self.direction)
        return self if self.direction == direction && path.first == prefix
        return self if self.direction == direction && path.first.to_s == "#{prefix}"

        self.class.new(
          base_message,
          path: [prefix, *path],
          direction: direction,
          meta: Undefined.equal?(meta) ? Undefined : meta
        )
      end

      private

      def direction_label
        case direction
        when :decode then "decode error: "
        when :encode then "encode error: "
        else EMPTY_STRING
        end
      end

      def path_label
        path.empty? ? EMPTY_STRING : "at #{path.map(&:inspect).join(".")}: "
      end

      def message_without_prefix
        message
          .sub(/\Adecode error: /, EMPTY_STRING)
          .sub(/\Aencode error: /, EMPTY_STRING)
          .sub(/\Aat (?:[^:]+): /, EMPTY_STRING)
      end
    end

    # Raised when a sum codec cannot choose exactly one branch while encoding
    #
    class AmbiguousCodecError < CodecError
      # @return [Array<Array>]
      attr_reader :branches

      # @api private
      def initialize(message, branches: EMPTY_ARRAY, **options)
        @branches = branches
        super(message, **options)
      end

      # @api private
      def with_path(prefix, direction = self.direction)
        copy = super
        copy.instance_variable_set(:@branches, branches)
        copy
      end
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
  end
end
