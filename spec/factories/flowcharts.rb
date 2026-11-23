FactoryBot.define do
  factory :flowchart do
    sequence(:name) { |n| "Flowchart #{n}" }
    description { "A sample flowchart for testing purposes" }
    customer

    configuration do
      {
        'elements' => [
          {
            'id' => 'element_1',
            'type' => 'start',
            'x' => 100,
            'y' => 100,
            'width' => 100,
            'height' => 45,
            'label' => 'Start',
            'properties' => { 'inputs' => [], 'outputs' => [] }
          },
          {
            'id' => 'element_2',
            'type' => 'process',
            'x' => 200,
            'y' => 200,
            'width' => 100,
            'height' => 45,
            'label' => 'Process',
            'properties' => { 'steps' => [], 'inputs' => [], 'outputs' => [] }
          },
          {
            'id' => 'element_3',
            'type' => 'end',
            'x' => 300,
            'y' => 300,
            'width' => 100,
            'height' => 45,
            'label' => 'End',
            'properties' => {}
          }
        ],
        'connections' => [
          {
            'id' => 'connection_1',
            'from' => 'element_1',
            'to' => 'element_2'
          },
          {
            'id' => 'connection_2',
            'from' => 'element_2',
            'to' => 'element_3'
          }
        ],
        'metadata' => {
          'canvas' => { 'width' => 1200, 'height' => 800 },
          'created_at' => Time.current.iso8601
        }
      }.to_json
    end

    trait :empty do
      configuration do
        {
          'elements' => [],
          'connections' => [],
          'metadata' => {
            'canvas' => { 'width' => 1200, 'height' => 800 },
            'created_at' => Time.current.iso8601
          }
        }.to_json
      end
    end

    trait :simple do
      configuration do
        {
          'elements' => [
            {
              'id' => 'start_1',
              'type' => 'start',
              'x' => 150,
              'y' => 100,
              'width' => 100,
              'height' => 45,
              'label' => 'Begin',
              'properties' => { 'inputs' => [], 'outputs' => [] }
            },
            {
              'id' => 'process_1',
              'type' => 'process',
              'x' => 150,
              'y' => 200,
              'width' => 100,
              'height' => 45,
              'label' => 'Process',
              'properties' => { 'steps' => [], 'inputs' => [], 'outputs' => [] }
            },
            {
              'id' => 'end_1',
              'type' => 'end',
              'x' => 150,
              'y' => 300,
              'width' => 100,
              'height' => 45,
              'label' => 'End',
              'properties' => {}
            }
          ],
          'connections' => [
            { 'id' => 'conn_1', 'from' => 'start_1', 'to' => 'process_1' },
            { 'id' => 'conn_2', 'from' => 'process_1', 'to' => 'end_1' }
          ],
          'metadata' => {
            'canvas' => { 'width' => 1200, 'height' => 800 },
            'created_at' => Time.current.iso8601
          }
        }.to_json
      end
    end

    trait :complex do
      name { "Complex Business Process" }
      description { "A complex flowchart with multiple elements and decision points" }

      configuration do
        {
          'elements' => [
            {
              'id' => 'start_1',
              'type' => 'start',
              'x' => 100,
              'y' => 50,
              'width' => 100,
              'height' => 45,
              'label' => 'Start Process',
              'properties' => { 'inputs' => [], 'outputs' => [] }
            },
            {
              'id' => 'process_1',
              'type' => 'process',
              'x' => 100,
              'y' => 150,
              'width' => 100,
              'height' => 45,
              'label' => 'Validate Input',
              'properties' => { 'steps' => [], 'inputs' => [], 'outputs' => [] }
            },
            {
              'id' => 'decision_1',
              'type' => 'decision',
              'x' => 100,
              'y' => 250,
              'width' => 100,
              'height' => 45,
              'label' => 'Valid?',
              'properties' => {
                'routeBy' => 'condition',
                'condition' => {
                  'type' => 'group', 'joins' => [],
                  'conditions' => [
                    { 'kind' => 'field', 'leftOperand' => 'ctx.valid', 'operator' => 'is_true', 'rightOperand' => '' }
                  ]
                }
              }
            },
            {
              'id' => 'process_2',
              'type' => 'process',
              'x' => 200,
              'y' => 350,
              'width' => 100,
              'height' => 45,
              'label' => 'Process Data',
              'properties' => { 'steps' => [], 'inputs' => [], 'outputs' => [] }
            },
            {
              'id' => 'process_3',
              'type' => 'process',
              'x' => 50,
              'y' => 350,
              'width' => 100,
              'height' => 45,
              'label' => 'Show Error',
              'properties' => { 'steps' => [], 'inputs' => [], 'outputs' => [] }
            },
            {
              'id' => 'decision_2',
              'type' => 'decision',
              'x' => 200,
              'y' => 400,
              'width' => 100,
              'height' => 45,
              'label' => 'Need report?',
              'properties' => {
                'routeBy' => 'condition',
                'condition' => {
                  'type' => 'group', 'joins' => [],
                  'conditions' => [
                    { 'kind' => 'field', 'leftOperand' => 'ctx.report', 'operator' => 'is_true', 'rightOperand' => '' }
                  ]
                }
              }
            },
            {
              'id' => 'document_1',
              'type' => 'process',
              'x' => 200,
              'y' => 500,
              'width' => 100,
              'height' => 45,
              'label' => 'Generate Report',
              'properties' => { 'steps' => [], 'inputs' => [], 'outputs' => [] }
            },
            {
              'id' => 'database_1',
              'type' => 'process',
              'x' => 320,
              'y' => 500,
              'width' => 100,
              'height' => 45,
              'label' => 'Save to DB',
              'properties' => { 'steps' => [], 'inputs' => [], 'outputs' => [] }
            },
            {
              'id' => 'end_1',
              'type' => 'end',
              'x' => 200,
              'y' => 550,
              'width' => 100,
              'height' => 45,
              'label' => 'End',
              'properties' => {}
            }
          ],
          'connections' => [
            { 'id' => 'conn_1', 'from' => 'start_1', 'to' => 'process_1' },
            { 'id' => 'conn_2', 'from' => 'process_1', 'to' => 'decision_1' },
            { 'id' => 'conn_3', 'from' => 'decision_1', 'to' => 'process_2', 'label' => 'Yes', 'matchValue' => 'true' },
            { 'id' => 'conn_4', 'from' => 'decision_1', 'to' => 'process_3', 'label' => 'No', 'matchValue' => 'false' },
            { 'id' => 'conn_5', 'from' => 'process_2', 'to' => 'decision_2' },
            { 'id' => 'conn_6', 'from' => 'decision_2', 'to' => 'document_1', 'label' => 'Yes', 'matchValue' => 'true' },
            { 'id' => 'conn_7', 'from' => 'decision_2', 'to' => 'database_1', 'label' => 'No', 'matchValue' => 'false' },
            { 'id' => 'conn_8', 'from' => 'document_1', 'to' => 'end_1' },
            { 'id' => 'conn_9', 'from' => 'database_1', 'to' => 'end_1' },
            { 'id' => 'conn_10', 'from' => 'process_3', 'to' => 'end_1' }
          ],
          'metadata' => {
            'canvas' => { 'width' => 1200, 'height' => 800 },
            'created_at' => Time.current.iso8601,
            'description' => 'Complex workflow with validation and multiple outputs'
          }
        }.to_json
      end
    end

    trait :with_invalid_json do
      configuration { 'invalid json string {' }
    end

    trait :shared_type do
      customer { nil }
      after(:build) { |record| record.skip_tenant_customer_assignment! }
    end

    trait :customer_specific_type do
      customer
    end

    trait :draft do
      status { :draft }
    end

    trait :launched_status do
      status { :launched }
    end

    trait :with_missing_input do
      configuration do
        {
          'elements' => [
            {
              'id' => 'start_1',
              'type' => 'start',
              'x' => 150,
              'y' => 100,
              'width' => 100,
              'height' => 45,
              'label' => 'Start',
              'properties' => {}
            },
            {
              'id' => 'process_1',
              'type' => 'process',
              'x' => 150,
              'y' => 200,
              'width' => 100,
              'height' => 45,
              'label' => 'Process',
              'properties' => {
                'steps' => [
                  { 'action' => 'api_call', 'config' => { 'url' => 'ctx[:missing_api_url]', 'method' => 'GET' } }
                ]
              }
            },
            {
              'id' => 'end_1',
              'type' => 'end',
              'x' => 150,
              'y' => 300,
              'width' => 100,
              'height' => 45,
              'label' => 'End',
              'properties' => {}
            }
          ],
          'connections' => [
            { 'id' => 'conn_1', 'from' => 'start_1', 'to' => 'process_1' },
            { 'id' => 'conn_2', 'from' => 'process_1', 'to' => 'end_1' }
          ],
          'metadata' => {
            'canvas' => { 'width' => 1200, 'height' => 800 },
            'created_at' => Time.current.iso8601
          }
        }.to_json
      end
    end
  end
end
