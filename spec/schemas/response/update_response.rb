# frozen_string_literal: true

# This file is autogenerated by Deimos, Do NOT modify
module Schemas; module Response
  ### Primary Schema Class ###
  # Autogenerated Schema for Record at com.my-namespace.response.UpdateResponse
  class UpdateResponse < Deimos::SchemaClass::Record

    ### Attribute Accessors ###
    # @return [String]
    attr_accessor :update_response_id

    # @override
    def initialize(update_response_id: nil)
      super
      self.update_response_id = update_response_id
    end

    # @override
    def schema
      'UpdateResponse'
    end

    # @override
    def namespace
      'com.my-namespace.response'
    end

    # @override
    def as_json(_opts={})
      {
        'update_response_id' => @update_response_id
      }
    end
  end
end; end
