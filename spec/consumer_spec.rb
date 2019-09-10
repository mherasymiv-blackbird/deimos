# frozen_string_literal: true

# :nodoc:
module ConsumerTest
  describe Deimos::Consumer do

    prepend_before(:each) do
      # :nodoc:
      consumer_class = Class.new(Deimos::Consumer) do
        schema 'MySchema'
        namespace 'com.my-namespace'
        key_config field: 'test_id'

        # :nodoc:
        def consume(_payload, _metadata)
          raise 'This should not be called unless call_original is set'
        end
      end
      stub_const('ConsumerTest::MyConsumer', consumer_class)
    end

    it 'should consume a message' do
      test_consume_message(MyConsumer,
                           'test_id' => 'foo',
                           'some_int' => 123) do |payload, _metadata|
                             expect(payload['test_id']).to eq('foo')
                           end
    end

    it 'should consume a message on a topic' do
      test_consume_message('my_consume_topic',
                           'test_id' => 'foo',
                           'some_int' => 123) do |payload, _metadata|
                             expect(payload['test_id']).to eq('foo')
                           end
    end

    it 'should fail on invalid message' do
      test_consume_invalid_message(MyConsumer, 'invalid' => 'key')
    end

    it 'should fail on message with extra fields' do
      test_consume_invalid_message(MyConsumer,
                                   'test_id' => 'foo',
                                   'some_int' => 123,
                                   'extra_field' => 'field name')
    end

    it 'should not fail when before_consume fails without reraising errors' do
      Deimos.configure { |config| config.reraise_consumer_errors = false }
      expect {
        test_consume_message(
          MyConsumer,
          { 'test_id' => 'foo',
            'some_int' => 123 },
          { skip_expectation: true }
        ) { raise 'OH NOES' }
      } .not_to raise_error
    end

    it 'should not fail when consume fails without reraising errors' do
      Deimos.configure { |config| config.reraise_consumer_errors = false }
      expect {
        test_consume_message(
          MyConsumer,
          { 'invalid' => 'key' },
          { skip_expectation: true }
        )
      } .not_to raise_error
    end

    it 'should call original' do
      expect {
        test_consume_message(MyConsumer,
                             { 'test_id' => 'foo', 'some_int' => 123 },
                             { call_original: true })
      }.to raise_error('This should not be called unless call_original is set')
    end

    describe 'decode_key' do

      it 'should use the key field in the value if set' do
        # actual decoding is disabled in test
        expect(MyConsumer.new.decode_key('test_id' => '123')).to eq('123')
        expect { MyConsumer.new.decode_key(123) }.to raise_error(NoMethodError)
      end

      it 'should use the key schema if set' do
        consumer_class = Class.new(Deimos::Consumer) do
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config schema: 'MySchema_key'
        end
        stub_const('ConsumerTest::MySchemaConsumer', consumer_class)
        expect(MyConsumer.new.decode_key('test_id' => '123')).to eq('123')
        expect { MyConsumer.new.decode_key(123) }.to raise_error(NoMethodError)
      end

      it 'should not decode if plain is set' do
        consumer_class = Class.new(Deimos::Consumer) do
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config plain: true
        end
        stub_const('ConsumerTest::MyNonEncodedConsumer', consumer_class)
        expect(MyNonEncodedConsumer.new.decode_key('123')).to eq('123')
      end

      it 'should error with nothing set' do
        consumer_class = Class.new(Deimos::Consumer) do
          schema 'MySchema'
          namespace 'com.my-namespace'
        end
        stub_const('ConsumerTest::MyErrorConsumer', consumer_class)
        expect { MyErrorConsumer.new.decode_key('123') }.
          to raise_error('No key config given - if you are not decoding keys, please use `key_config plain: true`')
      end

    end

    describe 'timestamps' do
      before(:each) do
        # :nodoc:
        consumer_class = Class.new(Deimos::Consumer) do
          schema 'MySchemaWithDateTimes'
          namespace 'com.my-namespace'
          key_config plain: true

          # :nodoc:
          def consume(_payload, _metadata)
            raise 'This should not be called unless call_original is set'
          end
        end
        stub_const('ConsumerTest::MyConsumer', consumer_class)
        stub_consumer(consumer_class)
      end

      it 'should consume a message' do
        expect(Deimos.config.metrics).to receive(:histogram).twice
        test_consume_message('my_consume_topic',
                             'test_id' => 'foo',
                             'some_int' => 123,
                             'updated_at' => Time.now.to_i,
                             'timestamp' => 2.minutes.ago.to_s) do |payload, _metadata|
                               expect(payload['test_id']).to eq('foo')
                             end
      end

      it 'should fail nicely when timestamp wrong format' do
        expect(Deimos.config.metrics).to receive(:histogram).twice
        test_consume_message('my_consume_topic',
                             'test_id' => 'foo',
                             'some_int' => 123,
                             'updated_at' => Time.now.to_i,
                             'timestamp' => 'dffdf') do |payload, _metadata|
                               expect(payload['test_id']).to eq('foo')
                             end
        test_consume_message('my_consume_topic',
                             'test_id' => 'foo',
                             'some_int' => 123,
                             'updated_at' => Time.now.to_i,
                             'timestamp' => '') do |payload, _metadata|
                               expect(payload['test_id']).to eq('foo')
                             end
      end

    end
  end
end
