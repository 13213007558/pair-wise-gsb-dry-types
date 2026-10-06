# frozen_string_literal: true

module Dry
  module Types
    # A type with explicitly declared external-to-domain and domain-to-external functions.
    # The encoder is the canonical representation and is used for round-trip assertions
    # when decoding is not injective.
    #
    # @api public
    class Codec
      include Type
      include Decorator
      include Builder
      include Printable
      include ::Dry::Equalizer(:type, :decoder, :encoder, :options, :meta, inspect: false, immutable: true)

      # @return [#call, nil]
      attr_reader :decoder

      # @return [#call, nil]
      attr_reader :encoder

      # @param [Type, Object] input
      # @param [#call, nil] decoder
      # @param [#call, nil] encoder
      # @param [Hash] options
      #
      # @api public
      def self.new(input, decoder = nil, encoder = nil, **options, &block)
        type = input.is_a?(Builder) ? input : Nominal.new(input)
        super(type, decoder, encoder || block, **options)
      end

      # @api private
      def initialize(type, decoder = nil, encoder = nil, **options)
        super(type, **options)
        @decoder = decoder
        @encoder = encoder
      end

      # @api private
      def call_unsafe(input)
        decode_unsafe(input)
      end

      # @api private
      def call_safe(input, &block)
        decode_safe(input, &block)
      end

      # @api private
      def try(input, &)
        result = decode_function(input)
        type.try(result, &)
      rescue CodecError => error
        failure = Result::Failure.new(input, error)
        block_given? ? yield(failure) : failure
      end

      # @api private
      def decode_unsafe(input)
        type.decode_unsafe(decode_function(input))
      rescue CodecError
        raise
      rescue ::StandardError => error
        raise DecodingError.new(error.message)
      end

      # @api private
      def decode_safe(input)
        decode_unsafe(input)
      rescue CodecError => error
        yield(error)
      end

      # @api private
      def encode_unsafe(input)
        if !encoder.nil?
          encoder.call(input)
        elsif !decoder.nil?
          raise EncodingError.new("type has no encoder (register an explicit encoder with Codec)")
        else
          type.encode_unsafe(input)
        end
      rescue CodecError
        raise
      rescue ::StandardError => error
        raise EncodingError.new(error.message)
      end

      # @api private
      def encode_safe(input)
        encode_unsafe(input)
      rescue CodecError => error
        yield(error)
      end

      # @return [Boolean]
      #
      # @api public
      def encodable?
        !encoder.nil? || (decoder.nil? && type.encodable?)
      end

      # Build another codec with an additional decoding step
      #
      # @return [Codec]
      #
      # @api public
      def constructor(new_fn = nil, **options, &block)
        function = new_fn || block
        next_decoder = decoder ? -> input { function.call(decoder.call(input)) } : function
        Codec.new(type, next_decoder, encoder, meta: meta, **options)
      end

      # @see Nominal#to_ast
      #
      # @api public
      def to_ast(meta: true)
        [:codec, [type.to_ast(meta: meta), !decoder.nil?, !encoder.nil?, meta_ast(meta)]]
      end

      # @api private
      def with(**new_options)
        return self if new_options.empty?

        self.class.new(type, decoder, encoder, **options, **new_options)
      end

      private

      # @api private
      def decode_function(input)
        return input if decoder.nil?

        decoder.call(input)
      rescue CodecError
        raise
      rescue ::StandardError => error
        raise DecodingError.new(error.message)
      end

      def __new__(new_type)
        self.class.new(new_type, decoder, encoder, **options)
      end
    end
  end
end
