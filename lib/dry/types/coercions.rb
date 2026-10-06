# frozen_string_literal: true

module Dry
  module Types
    # Common coercion functions used by the built-in `Params` and `JSON` types
    #
    # @api public
    module Coercions
      include Dry::Core::Constants

      # Exact decimal pattern accepted in addition to Rational() literals
      DECIMAL_STRING = /\A[+-]?(?:\d+|\d+\.\d*|\.\d+)(?:[eE][+-]?\d+)?\z/.freeze

      # Coerce a value to Rational without going through Float.
      #
      # Strings are parsed exactly: +"0.1"+ becomes +1/10+ rather than the
      # nearest binary floating point number.
      #
      # @param [Integer, Rational, String, Object] input
      #
      # @return [Rational]
      #
      # @raise [CoercionError]
      #
      # @api public
      def self.to_rational(input, &block)
        case input
        when ::Integer, ::Rational
          input.to_r
        when ::Float, ::BigDecimal
          input.to_r
        when ::String
          string_to_rational(input, &block)
        else
          if input.respond_to?(:to_r)
            input.to_r
          elsif block_given?
            return yield
          else
            raise CoercionError, "#{input.inspect} cannot be coerced to Rational"
          end
        end
      rescue ::ArgumentError, ::TypeError, CoercionError => exception
        CoercionError.handle(exception, &block)
      end

      # @api private
      def self.string_to_rational(string, &block)
        stripped = string.strip

        if stripped.empty?
          return handle_rational_failure("empty string cannot be coerced to Rational", &block)
        end

        if stripped.match?(DECIMAL_STRING)
          decimal_string_to_rational(stripped)
        else
          begin
            ::Kernel.Rational(stripped)
          rescue ::ArgumentError
            return handle_rational_failure(
              "#{string.inspect} cannot be coerced to Rational", &block
            )
          end
        end
      end
      private_class_method :string_to_rational

      # @api private
      def self.handle_rational_failure(message, &block)
        if block_given?
          yield
        else
          raise CoercionError, message
        end
      end
      private_class_method :handle_rational_failure

      # Parse an (optionally signed) decimal/scientific string exactly
      #
      # @api private
      def self.decimal_string_to_rational(string)
        sign = string.start_with?("-") ? -1 : 1
        unsigned = string.sub(/\A[+-]/, "")
        mantissa, exponent = unsigned.split(/[eE]/, 2)
        integer_part, fractional_part = mantissa.split(".", 2)
        integer_part = "0" if integer_part.nil? || integer_part.empty?
        fractional_part ||= ""

        digits = "#{integer_part}#{fractional_part}".to_i
        value = Rational(digits, 10 ** fractional_part.length)
        unless exponent.nil? || exponent.empty?
          power = 10 ** exponent.to_i.abs
          value = exponent.to_i.negative? ? (value / power) : (value * power)
        end
        sign * value
      end
      private_class_method :decimal_string_to_rational

      # @param [#to_str, Object] input
      #
      # @return [Date, Object]
      #
      # @see Date.parse
      #
      # @api public
      def to_date(input, &)
        if input.respond_to?(:to_str)
          begin
            ::Date.parse(input)
          rescue ::ArgumentError, ::RangeError => exception
            CoercionError.handle(exception, &)
          end
        elsif input.is_a?(::Date)
          input
        elsif block_given?
          yield
        else
          raise CoercionError, "#{input.inspect} is not a string"
        end
      end

      # @param [#to_str, Object] input
      #
      # @return [DateTime, Object]
      #
      # @see DateTime.parse
      #
      # @api public
      def to_date_time(input, &)
        if input.respond_to?(:to_str)
          begin
            ::DateTime.parse(input)
          rescue ::ArgumentError => exception
            CoercionError.handle(exception, &)
          end
        elsif input.is_a?(::DateTime)
          input
        elsif block_given?
          yield
        else
          raise CoercionError, "#{input.inspect} is not a string"
        end
      end

      # @param [#to_str, Object] input
      #
      # @return [Time, Object]
      #
      # @see Time.parse
      #
      # @api public
      def to_time(input, &)
        if input.respond_to?(:to_str)
          begin
            ::Time.parse(input)
          rescue ::ArgumentError => exception
            CoercionError.handle(exception, &)
          end
        elsif input.is_a?(::Time)
          input
        elsif block_given?
          yield
        else
          raise CoercionError, "#{input.inspect} is not a string"
        end
      end

      # @param [#to_sym, Object] input
      #
      # @return [Symbol, Object]
      #
      # @raise CoercionError
      #
      # @api public
      def to_symbol(input, &)
        input.to_sym
      rescue ::NoMethodError => exception
        CoercionError.handle(exception, &)
      end

      private

      # Checks whether String is empty
      #
      # @param [String, Object] value
      #
      # @return [Boolean]
      #
      # @api private
      def empty_str?(value) = EMPTY_STRING.eql?(value)
    end
  end
end
