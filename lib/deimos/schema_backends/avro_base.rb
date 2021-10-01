# frozen_string_literal: true

require_relative 'base'
require 'avro'
require 'avro_turf'
require 'avro_turf/mutable_schema_store'
require_relative 'avro_schema_coercer'

module Deimos
  module SchemaBackends
    # Encode / decode using Avro, either locally or via schema registry.
    class AvroBase < Base
      attr_accessor :schema_store

      # @override
      def initialize(schema:, namespace:)
        super(schema: schema, namespace: namespace)
        @schema_store = AvroTurf::MutableSchemaStore.new(path: Deimos.config.schema.path)
      end

      # @override
      def encode_key(key_id, key, topic: nil)
        @key_schema ||= _generate_key_schema(key_id)
        field_name = _field_name_from_schema(@key_schema)
        payload = { field_name => key }
        encode(payload, schema: @key_schema['name'], topic: topic)
      end

      # @override
      def decode_key(payload, key_id)
        @key_schema ||= _generate_key_schema(key_id)
        field_name = _field_name_from_schema(@key_schema)
        decode(payload, schema: @key_schema['name'])[field_name]
      end

      # :nodoc:
      def sql_type(field)
        type = field.type.type
        return type if %w(array map record).include?(type)

        if type == :union
          non_null = field.type.schemas.reject { |f| f.type == :null }
          if non_null.size > 1
            warn("WARNING: #{field.name} has more than one non-null type. Picking the first for the SQL type.")
          end
          return non_null.first.type
        end
        return type.to_sym if %w(float boolean).include?(type)
        return :integer if type == 'int'
        return :bigint if type == 'long'

        if type == 'double'
          warn('Avro `double` type turns into SQL `float` type. Please ensure you have the correct `limit` set.')
          return :float
        end

        :string
      end

      # @override
      def coerce_field(field, value)
        AvroSchemaCoercer.new(avro_schema).coerce_type(field.type, value)
      end

      # @override
      def schema_fields
        avro_schema.fields.map do |field|
          enum_values = field.type.type == 'enum' ? field.type.symbols : []
          SchemaField.new(field.name, field.type, enum_values, field.default)
        end
      end

      # @override
      def validate(payload, schema:)
        Avro::SchemaValidator.validate!(avro_schema(schema), payload,
                                        recursive: true,
                                        fail_on_extra_fields: true)
      end

      # @override
      # @return [Avro::Schema]
      def load_schema
        avro_schema
      end

      # @return [Boolean] If the schema is being used as a key schema
      def is_key_schema?
        is_consumer_key_schema? || is_producer_key_schema?
      end

      # @override
      def self.mock_backend
        :avro_validation
      end

      # @override
      def self.content_type
        'avro/binary'
      end

      # @param schema [Avro::Schema::NamedSchema] A named schema
      # @return [String]
      def self.schema_classname(schema)
        schema.name.underscore.camelize
      end

      # Converts Avro::Schema::NamedSchema's to String form for generated YARD docs.
      # Recursively handles the typing for Arrays, Maps and Unions.
      # @param avro_schema [Avro::Schema::NamedSchema]
      # @return [String] A string representation of the Type of this SchemaField
      def self.field_type(avro_schema)
        case avro_schema.type_sym
        when :string, :boolean
          avro_schema.type_sym.to_s.titleize
        when :int, :long
          'Integer'
        when :float, :double
          'Float'
        when :record, :enum
          "Deimos::#{schema_classname(avro_schema)}"
        when :array
          arr_t = field_type(Deimos::SchemaField.new('n/a', avro_schema.items).type)
          "Array<#{arr_t}>"
        when :map
          map_t = field_type(Deimos::SchemaField.new('n/a', avro_schema.values).type)
          "Hash<String, #{map_t}>"
        when :union
          types = avro_schema.schemas.map do |t|
            field_type(Deimos::SchemaField.new('n/a', t).type)
          end
          types.join(', ')
        when :null
          'nil'
        end
      end

    private

      # @param schema [String]
      # @return [Avro::Schema]
      def avro_schema(schema=nil)
        schema ||= @schema
        @schema_store.find(schema, @namespace)
      end

      # Generate a key schema from the given value schema and key ID. This
      # is used when encoding or decoding keys from an existing value schema.
      # @param key_id [Symbol]
      # @return [Hash]
      def _generate_key_schema(key_id)
        key_field = avro_schema.fields.find { |f| f.name == key_id.to_s }
        name = _key_schema_name(@schema)
        key_schema = {
          'type' => 'record',
          'name' => name,
          'namespace' => @namespace,
          'doc' => "Key for #{@namespace}.#{@schema} - autogenerated by Deimos",
          'fields' => [
            {
              'name' => key_id,
              'type' => key_field.type.type_sym.to_s
            }
          ]
        }
        @schema_store.add_schema(key_schema)
        key_schema
      end

      # @param value_schema [Hash]
      # @return [String]
      def _field_name_from_schema(value_schema)
        raise "Schema #{@schema} not found!" if value_schema.nil?
        if value_schema['fields'].nil? || value_schema['fields'].empty?
          raise "Schema #{@schema} has no fields!"
        end

        value_schema['fields'][0]['name']
      end

      # @param schema [String]
      # @return [String]
      def _key_schema_name(schema)
        "#{schema}_key"
      end

      # @return [Boolean] If the schema is being used in a Consumer
      def is_consumer_key_schema?
        @consumer_key_schemas ||= Deimos.config.consumer_objects.map { |c| c.try(:key_schema) }.
          uniq.compact
        @consumer_key_schemas.include? avro_schema.name
      end

      # @return [Boolean] If the schema is being used in a Producer
      def is_producer_key_schema?
        @producer_key_schemas ||= Deimos.config.producer_objects.map { |c| c.try(:key_schema) }.
          uniq.compact
        @producer_key_schemas.include? avro_schema.name
      end

    end
  end
end
