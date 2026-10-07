# frozen_string_literal: true

module Dry
  module Types
    # Pairs explicit decoding of external data with encoding back to that representation
    #
    # @api public
    class Codec
      include Type
      include Options
      include Meta
      include Builder
      include Printable
      include ::Dry::Equalizer(:external, :internal, :options, :meta, inspect: false, immutable: true)

      IDENTITY = :itself.to_proc

      # @return [Type]
      attr_reader :external

      # @return [Type]
      attr_reader :internal

      # @return [#call]
      attr_reader :decoder

      # @return [#call]
      attr_reader :encoder

      # @param [Type] external
      # @param [Type] internal
      # @param [#call] decoder
      # @param [#call] encoder
      #
      # @api public
      def initialize(external, internal, decoder: IDENTITY, encoder: IDENTITY, **options)
        @external = external
        @internal = internal
        @decoder = decoder
        @encoder = encoder

        super(external, internal, **options, decoder: decoder, encoder: encoder)
      end

      # Decode using this codec while applying the type as an ordinary dry type
      #
      # @return [Object]
      #
      # @api private
      def call_unsafe(input) = decode_unsafe(input)

      # @api private
      def call_safe(input, &block)
        decode_unsafe(input)
      rescue CodecError
        yield input
      end

      # @return [Result::Success, Result::Failure]
      #
      # @api public
      def try(input, &block)
        result = decode_unsafe(input)
        result.is_a?(Result) ? result : Result::Success.new(result)
      rescue CodecError => exception
        failure = Result::Failure.new(input, exception)
        block_given? ? block.call(failure) : failure
      end

      # @return [Object]
      #
      # @api public
      def decode_unsafe(input)
        external_value = conform(external, input, :decode)
        decoded = invoke(decoder, external_value, :decode)
        assert(internal, decoded, :decode, "decoded value")
        decoded
      end

      # @return [Object]
      #
      # @api public
      def encode_unsafe(input, **)
        assert(internal, input, :encode, "internal value")
        encoded = invoke(encoder, input, :encode)
        conform_external(encoded, :encode, "encoded value")
      end

      # @return [true]
      #
      # @api public
      def codec? = true

      # @return [Boolean]
      #
      # @api public
      def default? = internal.default?

      # @return [Boolean]
      #
      # @api public
      def constrained? = internal.constrained?

      # @return [Boolean]
      #
      # @api public
      def optional? = internal.optional?

      # @return [Boolean]
      #
      # @api private
      def primitive?(value) = internal.primitive?(value)

      # @return [String]
      #
      # @api public
      def name = "Codec<#{external.name} => #{internal.name}>"

      # Attach an explicit external discriminator tag
      #
      # @return [Codec::Tagged]
      #
      # @api public
      def tag(label, key: :type) = Tagged.new(self, label, key: key)

      # @return [Array]
      #
      # @api public
      def to_ast(meta: true)
        [:codec, [external.to_ast(meta: meta), internal.to_ast(meta: meta), meta_ast(meta)]]
      end

      # @return [Codec]
      #
      # @api public
      def lax = Codec.new(external.lax, internal.lax, decoder: decoder, encoder: encoder, meta: meta)

      # @return [Proc]
      #
      # @api public
      def to_proc = proc { decode(_1) }

      # @return [Result::Success]
      #
      # @api public
      def success(input) = Result::Success.new(input)

      # @return [Result::Failure]
      #
      # @api public
      def failure(input, error)
        raise ::ArgumentError, "error must be a CoercionError" unless error.is_a?(CoercionError)

        Result::Failure.new(input, error)
      end

      private

      def assert(type, value, direction, label = "value")
        result = type.try(value)
        return result.input if result.success?

        error = result.error
        message = error.respond_to?(:message) ? error.message : error.to_s
        raise CodecError.build("#{label} #{message}", direction: direction)
      rescue ::StandardError => exception
        raise CodecError.build(exception.message, direction: direction)
      end

      def assert_external(type, value, direction, label = "value")
        if type.respond_to?(:conforms_without_codec?)
          return value if type.conforms_without_codec?(value, direction)

          raise CodecError.build("#{label} #{value.inspect} violates external schema", direction: direction)
        end

        assert(type, value, direction, label)
      end

      def conform_external(value, direction, label = "value")
        if direction == :encode && external.respond_to?(:encoder?) && external.encoder?
          external.encode_unsafe(value)
        else
          assert_external(external, value, direction, label)
        end
      end

      alias_method :conform, :assert

      def invoke(function, value, direction)
        function.call(value)
      rescue CodecError
        exception = $!
        if exception.direction.nil?
          meta = Undefined.equal?(exception.meta) ? Undefined : exception.meta
          raise CodecError.build(
            exception.base_message,
            path: exception.path,
            direction: direction,
            meta: meta
          )
        end

        raise exception
      rescue CoercionError, ConstraintError, ::StandardError => exception
        raise CodecError.build(exception.message, direction: direction)
      end

      # An explicitly tagged branch of a sum codec
      #
      # @api public
      class Tagged
        include Type
        include Decorator
        include Builder
        include Printable
        include ::Dry::Equalizer(:type, :label, :key, inspect: false, immutable: true)

        # @return [Codec]
        attr_reader :type

        # @return [Object]
        attr_reader :label

        # @return [Symbol]
        attr_reader :key

        # @param [Codec] codec
        # @param [Object] label
        # @param [Symbol] key
        #
        # @api private
        def initialize(codec, label, key: :type, **options)
          super(codec, **options, label: label, key: key)
          @label = label
          @key = key
          freeze
        end

        # @return [Object]
        #
        # @api private
        def call_unsafe(input) = decode_unsafe(input)

        # @return [Object]
        #
        # @api private
        def call_safe(input, &block)
          decode_unsafe(input)
        rescue CodecError
          yield input
        end

        # @return [Result::Success, Result::Failure]
        #
        # @api public
        def try(input, &block)
          result = decode_unsafe(input)
          result.is_a?(Result) ? result : Result::Success.new(result)
        rescue CodecError => exception
          failure = Result::Failure.new(input, exception)
          block_given? ? block.call(failure) : failure
        end

        # @return [true]
        #
        # @api public
        def codec? = true

        # @return [Object]
        #
        # @api public
        def decode_unsafe(input)
          unless input.is_a?(::Hash) && input.key?(key)
            raise CodecError.build("missing tag #{key.inspect}", direction: :decode)
          end

          tag = input.fetch(key)
          unless tag == label
            raise CodecError.build(
              "expected tag #{label.inspect}, got #{tag.inspect}",
              direction: :decode
            )
          end

          type.decode_unsafe(input.except(key))
        end

        # @return [Object]
        #
        # @api public
        def encode_unsafe(input, **)
          encoded = type.encode_unsafe(input)
          unless encoded.is_a?(::Hash)
            raise CodecError.build("tagged codec must encode a Hash", direction: :encode)
          end
          { key => label }.merge(encoded.except(key))
        end

        # @return [Boolean]
        #
        # @api private
        def primitive?(value) = type.primitive?(value)

        # @return [String]
        #
        # @api public
        def name = "Tagged(#{label.inspect})<#{type.name}>"

        # @return [Array]
        #
        # @api public
        def to_ast(meta: true) = [:tagged, [type.to_ast(meta: meta), label, key]]

        # @return [Result::Success]
        #
        # @api public
        def success(input) = type.success(input)

        # @return [Result::Failure]
        #
        # @api public
        def failure(input, error) = type.failure(input, error)

        # @return [Tagged]
        #
        # @api public
        def lax = __new__(type.lax)
      end
    end
  end
end
