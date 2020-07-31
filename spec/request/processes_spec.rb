require 'spec_helper'
require 'request_spec_shared_examples'

RSpec.describe 'Processes' do
  let(:space) { VCAP::CloudController::Space.make }
  let(:app_model) { VCAP::CloudController::AppModel.make(space: space, name: 'my_app', droplet: droplet) }
  let(:droplet) { VCAP::CloudController::DropletModel.make }
  let(:developer) { make_developer_for_space(space) }
  let(:developer_headers) { headers_for(developer, user_name: user_name) }
  let(:user) { VCAP::CloudController::User.make }
  let(:admin_header) { admin_headers_for(user) }
  let(:user_name) { 'ProcHudson' }
  let(:build_client) { instance_double(HTTPClient, post: nil) }
  let(:metadata) do
    {
      labels: {
        release: 'stable',
        'seriouseats.com/potato' => 'mashed'
      },
      annotations: { 'checksum' => 'SHA' },
    }
  end
  before do
    allow_any_instance_of(::Diego::Client).to receive(:build_client).and_return(build_client)
  end

  describe 'GET /v3/processes' do
    let!(:web_revision) { VCAP::CloudController::RevisionModel.make }

    let!(:web_process) {
      VCAP::CloudController::ProcessModel.make(
        :process,
        app:        app_model,
        revision:   web_revision,
        type:       'web',
        instances:  2,
        memory:     1024,
        disk_quota: 1024,
        command:    'rackup',
      )
    }
    let!(:worker_process) {
      VCAP::CloudController::ProcessModel.make(
        :process,
        app:        app_model,
        type:       'worker',
        instances:  1,
        memory:     100,
        disk_quota: 200,
        command:    'start worker',
      )
    }

    before { VCAP::CloudController::ProcessModel.make(:process, app: app_model) }

    it_behaves_like 'request_spec_shared_examples.rb list query endpoint' do
      let(:message) { VCAP::CloudController::ProcessesListMessage }
      let(:request) { '/v3/processes' }
      let(:user_header) { developer_headers }

      let(:excluded_params) {
        [
          :app_guid
        ]
      }
      let(:params) do
        {
          guids: ['foo', 'bar'],
          space_guids: ['foo', 'bar'],
          organization_guids: ['foo', 'bar'],
          types: ['foo', 'bar'],
          app_guids: ['foo', 'bar'],
          page:   '2',
          per_page:   '10',
          order_by:   'updated_at',
          label_selector:   'foo,bar',
        }
      end
    end

    it_behaves_like 'list_endpoint_with_common_filters' do
      let(:resource_klass) { VCAP::CloudController::ProcessModel }

      let(:api_call) do
        lambda { |headers, filters| get "/v3/processes?#{filters}", nil, headers }
      end
    end

    it 'returns a paginated list of processes' do
      get '/v3/processes?per_page=2', nil, developer_headers

      expected_response = {
        'pagination' => {
          'total_results' => 3,
          'total_pages'   => 2,
          'first'         => { 'href' => "#{link_prefix}/v3/processes?page=1&per_page=2" },
          'last'          => { 'href' => "#{link_prefix}/v3/processes?page=2&per_page=2" },
          'next'          => { 'href' => "#{link_prefix}/v3/processes?page=2&per_page=2" },
          'previous'      => nil,
        },
        'resources' => [
          {
            'guid' => web_process.guid,
            'relationships' => {
              'app' => { 'data' => { 'guid' => app_model.guid } },
              'revision' => {
                'data' => {
                  'guid' => web_revision.guid
                }
              },
            },
            'type'         => 'web',
            'command'      => '[PRIVATE DATA HIDDEN IN LISTS]',
            'instances'    => 2,
            'memory_in_mb' => 1024,
            'disk_in_mb'   => 1024,
            'health_check' => {
              'type' => 'port',
              'data' => {
                'timeout' => nil,
                'invocation_timeout' => nil
              }
            },
            'metadata' => { 'annotations' => {}, 'labels' => {} },
            'created_at'   => iso8601,
            'updated_at'   => iso8601,
            'links'        => {
              'self'  => { 'href' => "#{link_prefix}/v3/processes/#{web_process.guid}" },
              'scale' => { 'href' => "#{link_prefix}/v3/processes/#{web_process.guid}/actions/scale", 'method' => 'POST' },
              'app'   => { 'href' => "#{link_prefix}/v3/apps/#{app_model.guid}" },
              'space' => { 'href' => "#{link_prefix}/v3/spaces/#{space.guid}" },
              'stats' => { 'href' => "#{link_prefix}/v3/processes/#{web_process.guid}/stats" },
            },
          },
          {
            'guid' => worker_process.guid,
            'relationships' => {
              'app' => { 'data' => { 'guid' => app_model.guid } },
              'revision' => nil,
            },
            'type'         => 'worker',
            'command'      => '[PRIVATE DATA HIDDEN IN LISTS]',
            'instances'    => 1,
            'memory_in_mb' => 100,
            'disk_in_mb'   => 200,
            'health_check' => {
              'type' => 'port',
              'data' => {
                'timeout' => nil,
                'invocation_timeout' => nil
              }
            },
            'metadata' => { 'annotations' => {}, 'labels' => {} },
            'created_at'   => iso8601,
            'updated_at'   => iso8601,
            'links'        => {
              'self'  => { 'href' => "#{link_prefix}/v3/processes/#{worker_process.guid}" },
              'scale' => { 'href' => "#{link_prefix}/v3/processes/#{worker_process.guid}/actions/scale", 'method' => 'POST' },
              'app'   => { 'href' => "#{link_prefix}/v3/apps/#{app_model.guid}" },
              'space' => { 'href' => "#{link_prefix}/v3/spaces/#{space.guid}" },
              'stats' => { 'href' => "#{link_prefix}/v3/processes/#{worker_process.guid}/stats" },
            },
          }
        ]
      }

      parsed_response = MultiJson.load(last_response.body)

      expect(last_response.status).to eq(200)
      expect(parsed_response).to be_a_response_like(expected_response)
    end

    it 'filters by label selectors' do
      VCAP::CloudController::ProcessLabelModel.make(key_name: 'fruit', value: 'strawberry', process: worker_process)

      get '/v3/processes?label_selector=fruit=strawberry', {}, developer_headers

      expected_pagination = {
        'total_results' => 1,
        'total_pages'   => 1,
        'first'         => { 'href' => "#{link_prefix}/v3/processes?label_selector=fruit%3Dstrawberry&page=1&per_page=50" },
        'last'          => { 'href' => "#{link_prefix}/v3/processes?label_selector=fruit%3Dstrawberry&page=1&per_page=50" },
        'next'          => nil,
        'previous'      => nil
      }

      parsed_response = MultiJson.load(last_response.body)

      expect(last_response.status).to eq(200)
      expect(parsed_response['resources'].count).to eq(1)
      expect(parsed_response['resources'][0]['guid']).to eq(worker_process.guid)
      expect(parsed_response['pagination']).to eq(expected_pagination)
    end

    context 'faceted list' do
      context 'by types' do
        it 'returns only the matching processes' do
          get '/v3/processes?per_page=2&types=worker,doesnotexist', nil, developer_headers

          expected_pagination = {
            'total_results' => 1,
            'total_pages'   => 1,
            'first'         => { 'href' => "#{link_prefix}/v3/processes?page=1&per_page=2&types=worker%2Cdoesnotexist" },
            'last'          => { 'href' => "#{link_prefix}/v3/processes?page=1&per_page=2&types=worker%2Cdoesnotexist" },
            'next'          => nil,
            'previous'      => nil,
          }

          expect(last_response.status).to eq(200)

          parsed_response = MultiJson.load(last_response.body)

          returned_guids = parsed_response['resources'].map { |i| i['guid'] }
          expect(returned_guids).to match_array([worker_process.guid])
          expect(parsed_response['pagination']).to be_a_response_like(expected_pagination)
        end
      end

      context 'by space_guids' do
        let(:other_space) { VCAP::CloudController::Space.make(organization: space.organization) }
        let(:other_app_model) { VCAP::CloudController::AppModel.make(space: other_space) }
        let!(:other_space_process) {
          VCAP::CloudController::ProcessModel.make(
            :process,
            app:        other_app_model,
            type:       'web',
            instances:  2,
            memory:     1024,
            disk_quota: 1024,
            command:    'rackup',
          )
        }

        before do
          other_space.add_developer developer
        end

        it 'returns only the matching processes' do
          get "/v3/processes?per_page=2&space_guids=#{other_space.guid}", nil, developer_headers

          expected_pagination = {
            'total_results' => 1,
            'total_pages'   => 1,
            'first'         => { 'href' => "#{link_prefix}/v3/processes?page=1&per_page=2&space_guids=#{other_space.guid}" },
            'last'          => { 'href' => "#{link_prefix}/v3/processes?page=1&per_page=2&space_guids=#{other_space.guid}" },
            'next'          => nil,
            'previous'      => nil,
          }

          expect(last_response.status).to eq(200)

          parsed_response = MultiJson.load(last_response.body)

          returned_guids = parsed_response['resources'].map { |i| i['guid'] }
          expect(returned_guids).to match_array([other_space_process.guid])
          expect(parsed_response['pagination']).to be_a_response_like(expected_pagination)
        end
      end

      context 'by organization guids' do
        let(:other_space) { VCAP::CloudController::Space.make }
        let!(:other_org) { other_space.organization }
        let!(:other_space_process) {
          VCAP::CloudController::ProcessModel.make(
            :process,
            app:        other_app_model,
            type:       'web',
            instances:  2,
            memory:     1024,
            disk_quota: 1024,
            command:    'rackup',
          )
        }
        let(:other_app_model) { VCAP::CloudController::AppModel.make(space: other_space) }
        let(:developer) { make_developer_for_space(other_space) }

        it 'returns only the matching processes' do
          get "/v3/processes?per_page=2&organization_guids=#{other_org.guid}", nil, developer_headers

          expected_pagination = {
            'total_results' => 1,
            'total_pages'   => 1,
            'first'         => { 'href' => "#{link_prefix}/v3/processes?organization_guids=#{other_org.guid}&page=1&per_page=2" },
            'last'          => { 'href' => "#{link_prefix}/v3/processes?organization_guids=#{other_org.guid}&page=1&per_page=2" },
            'next'          => nil,
            'previous'      => nil,
          }

          expect(last_response.status).to eq(200)

          parsed_response = MultiJson.load(last_response.body)

          returned_guids = parsed_response['resources'].map { |i| i['guid'] }
          expect(returned_guids).to match_array([other_space_process.guid])
          expect(parsed_response['pagination']).to be_a_response_like(expected_pagination)
        end
      end

      context 'by app guids' do
        let(:desired_app) { VCAP::CloudController::AppModel.make(space: space) }
        let!(:desired_process) do
          VCAP::CloudController::ProcessModel.make(:process,
            app:        desired_app,
            type:       'persnickety',
            instances:  3,
            memory:     2048,
            disk_quota: 2048,
            command:    'at ease'
          )
        end

        it 'returns only the matching processes' do
          get "/v3/processes?per_page=2&app_guids=#{desired_app.guid}", nil, developer_headers

          expected_pagination = {
            'total_results' => 1,
            'total_pages'   => 1,
            'first'         => { 'href' => "#{link_prefix}/v3/processes?app_guids=#{desired_app.guid}&page=1&per_page=2" },
            'last'          => { 'href' => "#{link_prefix}/v3/processes?app_guids=#{desired_app.guid}&page=1&per_page=2" },
            'next'          => nil,
            'previous'      => nil,
          }

          expect(last_response.status).to eq(200)

          parsed_response = MultiJson.load(last_response.body)

          returned_guids = parsed_response['resources'].map { |i| i['guid'] }
          expect(returned_guids).to match_array([desired_process.guid])
          expect(parsed_response['pagination']).to be_a_response_like(expected_pagination)
        end
      end

      context 'by guids' do
        it 'returns only the matching processes' do
          get "/v3/processes?per_page=2&guids=#{web_process.guid},#{worker_process.guid}", nil, developer_headers

          expected_pagination = {
            'total_results' => 2,
            'total_pages'   => 1,
            'first'         => { 'href' => "#{link_prefix}/v3/processes?guids=#{web_process.guid}%2C#{worker_process.guid}&page=1&per_page=2" },
            'last'          => { 'href' => "#{link_prefix}/v3/processes?guids=#{web_process.guid}%2C#{worker_process.guid}&page=1&per_page=2" },
            'next'          => nil,
            'previous'      => nil,
          }

          expect(last_response.status).to eq(200)

          parsed_response = MultiJson.load(last_response.body)

          returned_guids = parsed_response['resources'].map { |i| i['guid'] }
          expect(returned_guids).to match_array([web_process.guid, worker_process.guid])
          expect(parsed_response['pagination']).to be_a_response_like(expected_pagination)
        end
      end
    end
  end

  describe 'GET /v3/processes/:guid' do
    it 'retrieves the process' do
      revision = VCAP::CloudController::RevisionModel.make
      process = VCAP::CloudController::ProcessModel.make(
        :process,
        app:        app_model,
        revision:   revision,
        type:       'web',
        instances:  2,
        memory:     1024,
        disk_quota: 1024,
        command:    'rackup',
      )

      get "/v3/processes/#{process.guid}", nil, developer_headers

      expected_response = {
        'guid'         => process.guid,
        'type'         => 'web',
        'relationships' => {
          'app' => { 'data' => { 'guid' => app_model.guid } },
          'revision' => { 'data' => { 'guid' => revision.guid } },
        },
        'command'      => 'rackup',
        'instances'    => 2,
        'memory_in_mb' => 1024,
        'disk_in_mb'   => 1024,
        'health_check' => {
          'type' => 'port',
          'data' => {
            'timeout' => nil,
            'invocation_timeout' => nil
          }
        },
        'metadata' => { 'annotations' => {}, 'labels' => {} },
        'created_at'   => iso8601,
        'updated_at'   => iso8601,
        'links'        => {
          'self'  => { 'href' => "#{link_prefix}/v3/processes/#{process.guid}" },
          'scale' => { 'href' => "#{link_prefix}/v3/processes/#{process.guid}/actions/scale", 'method' => 'POST' },
          'app'   => { 'href' => "#{link_prefix}/v3/apps/#{app_model.guid}" },
          'space' => { 'href' => "#{link_prefix}/v3/spaces/#{space.guid}" },
          'stats' => { 'href' => "#{link_prefix}/v3/processes/#{process.guid}/stats" },
        },
      }

      parsed_response = MultiJson.load(last_response.body)

      expect(last_response.status).to eq(200)
      expect(parsed_response).to be_a_response_like(expected_response)
    end

    it 'redacts information for auditors' do
      process = VCAP::CloudController::ProcessModel.make(:process, app: app_model, command: 'rackup')

      auditor = VCAP::CloudController::User.make
      space.organization.add_user(auditor)
      space.add_auditor(auditor)

      get "/v3/processes/#{process.guid}", nil, headers_for(auditor)

      parsed_response = MultiJson.load(last_response.body)

      expect(last_response.status).to eq(200)
      expect(parsed_response['command']).to eq('[PRIVATE DATA HIDDEN]')
    end
  end

  describe 'GET stats' do
    let(:process) { VCAP::CloudController::ProcessModel.make(:process, type: 'worker', app: app_model) }
    let(:net_info_1) {
      {
        address: '1.2.3.4',
        ports: [
          {
            host_port: 8080,
            container_port: 1234,
            host_tls_proxy_port: 61002,
            container_tls_proxy_port: 61003
          },
          {
            host_port: 3000,
            container_port: 4000,
            host_tls_proxy_port: 61006,
            container_tls_proxy_port: 61007
          }
        ]
      }
    }

    let(:stats_for_process) do
      {
        0 => {
          state: 'RUNNING',
          details: 'some-details',
          isolation_segment: 'very-isolated',
          stats: {
            name: process.name,
            uris: process.uris,
            host: 'toast',
            net_info: net_info_1,
            uptime: 12345,
            mem_quota:  process[:memory] * 1024 * 1024,
            disk_quota: process[:disk_quota] * 1024 * 1024,
            fds_quota: process.file_descriptors,
            usage: {
              time: usage_time,
              cpu:  80,
              mem:  128,
              disk: 1024,
            }
          }
        },
      }
    end

    let(:instances_reporters) { double(:instances_reporters) }
    let(:usage_time) { Time.now.utc.to_s }

    let(:expected_response) do
      {
      'resources' => [{
        'type'           => 'worker',
        'index'          => 0,
        'state'          => 'RUNNING',
        'isolation_segment' => 'very-isolated',
        'details' => 'some-details',
        'usage' => {
          'time' => usage_time,
          'cpu'  => 80,
          'mem'  => 128,
          'disk' => 1024,
        },
        'host'           => 'toast',
        'instance_ports' => [
          {
            'external' => 8080,
            'internal' => 1234,
            'external_tls_proxy_port' => 61002,
            'internal_tls_proxy_port' => 61003
          },
          {
            'external' => 3000,
            'internal' => 4000,
            'external_tls_proxy_port' => 61006,
            'internal_tls_proxy_port' => 61007
          }
        ],
        'uptime'         => 12345,
        'mem_quota'      => 1073741824,
        'disk_quota'     => 1073741824,
        'fds_quota'      => 16384
      }]
    }
    end

    before do
      CloudController::DependencyLocator.instance.register(:instances_reporters, instances_reporters)
      allow(instances_reporters).to receive(:stats_for_app).and_return(stats_for_process)
    end

    describe 'GET /v3/processes/:guid/stats' do
      context 'route integrity is enabled' do
        it 'retrieves the stats for a process' do
          get "/v3/processes/#{process.guid}/stats", nil, developer_headers

          parsed_response = MultiJson.load(last_response.body)

          expect(last_response.status).to eq(200)
          expect(parsed_response).to be_a_response_like(expected_response)
        end
      end
    end

    describe 'GET /v3/apps/:guid/processes/:type/stats' do
      it 'retrieves the stats for a process belonging to an app' do
        get "/v3/apps/#{app_model.guid}/processes/worker/stats", nil, developer_headers

        parsed_response = MultiJson.load(last_response.body)

        expect(last_response.status).to eq(200)
        expect(parsed_response).to be_a_response_like(expected_response)
      end
    end
  end

  describe 'PATCH /v3/processes/:guid' do
    it 'updates the process' do
      revision = VCAP::CloudController::RevisionModel.make
      process = VCAP::CloudController::ProcessModel.make(
        :process,
        app:                  app_model,
        revision:             revision,
        type:                 'web',
        instances:            2,
        memory:               1024,
        disk_quota:           1024,
        command:              'rackup',
        ports:                [4444, 5555],
        health_check_type:    'port',
        health_check_timeout: 10
      )

      update_request = {
        command:      'new command',
        health_check: {
          type: 'process',
          data: {
            timeout: 20
          }
        },
        metadata: metadata,
      }.to_json

      patch "/v3/processes/#{process.guid}", update_request, developer_headers.merge('CONTENT_TYPE' => 'application/json')

      expected_response = {
        'guid' => process.guid,
        'relationships' => {
          'app' => { 'data' => { 'guid' => app_model.guid } },
          'revision' => { 'data' => { 'guid' => revision.guid } },
        },
        'type'         => 'web',
        'command'      => 'new command',
        'instances'    => 2,
        'memory_in_mb' => 1024,
        'disk_in_mb'   => 1024,
        'health_check' => {
          'type' => 'process',
          'data' => {
            'timeout' => 20,
            'invocation_timeout' => nil
          }
        },
        'created_at'   => iso8601,
        'updated_at'   => iso8601,
        'links'        => {
          'self'  => { 'href' => "#{link_prefix}/v3/processes/#{process.guid}" },
          'scale' => { 'href' => "#{link_prefix}/v3/processes/#{process.guid}/actions/scale", 'method' => 'POST' },
          'app'   => { 'href' => "#{link_prefix}/v3/apps/#{app_model.guid}" },
          'space' => { 'href' => "#{link_prefix}/v3/spaces/#{space.guid}" },
          'stats' => { 'href' => "#{link_prefix}/v3/processes/#{process.guid}/stats" },
        },
        'metadata' => {
          'labels' => {
            'release' => 'stable',
            'seriouseats.com/potato' => 'mashed',
          },
          'annotations' => { 'checksum' => 'SHA' },
        },
      }

      parsed_response = MultiJson.load(last_response.body)

      expect(last_response.status).to eq(200)
      expect(parsed_response).to be_a_response_like(expected_response)

      process.reload
      expect(process.command).to eq('new command')
      expect(process.health_check_type).to eq('process')
      expect(process.health_check_timeout).to eq(20)

      event = VCAP::CloudController::Event.last
      expect(event.values).to include({
        type:              'audit.app.process.update',
        actee:             app_model.guid,
        actee_type:        'app',
        actee_name:        'my_app',
        actor:             developer.guid,
        actor_type:        'user',
        actor_username:    user_name,
        space_guid:        space.guid,
        organization_guid: space.organization.guid
      })
      expect(event.metadata).to eq({
        'process_guid' => process.guid,
        'process_type' => 'web',
        'request'      => {
          'command'      => '[PRIVATE DATA HIDDEN]',
          'health_check' => {
            'type' => 'process',
            'data' => {
              'timeout' => 20,
            }
          },
          'metadata' => {
            'labels' => {
              'release' => 'stable',
              'seriouseats.com/potato' => 'mashed',
            },
            'annotations' => { 'checksum' => 'SHA' },
          }
        }
      })
    end
  end

  describe 'POST /v3/processes/:guid/actions/scale' do
    it 'scales the process' do
      process = VCAP::CloudController::ProcessModel.make(
        :process,
        app:        app_model,
        type:       'web',
        instances:  2,
        memory:     1024,
        disk_quota: 1024,
        command:    'rackup',
      )

      scale_request = {
        instances:    5,
        memory_in_mb: 10,
        disk_in_mb:   20,
      }

      post "/v3/processes/#{process.guid}/actions/scale", scale_request.to_json, developer_headers

      expected_response = {
        'guid'         => process.guid,
        'type'         => 'web',
        'relationships' => {
          'app' => { 'data' => { 'guid' => app_model.guid } },
          'revision' => nil,
        },
        'command'      => 'rackup',
        'instances'    => 5,
        'memory_in_mb' => 10,
        'disk_in_mb'   => 20,
        'health_check' => {
          'type' => 'port',
          'data' => {
            'timeout' => nil,
            'invocation_timeout' => nil
          }
        },
        'created_at'   => iso8601,
        'updated_at'   => iso8601,
        'metadata' => { 'annotations' => {}, 'labels' => {} },
        'links' => {
          'self'  => { 'href' => "#{link_prefix}/v3/processes/#{process.guid}" },
          'scale' => { 'href' => "#{link_prefix}/v3/processes/#{process.guid}/actions/scale", 'method' => 'POST' },
          'app'   => { 'href' => "#{link_prefix}/v3/apps/#{app_model.guid}" },
          'space' => { 'href' => "#{link_prefix}/v3/spaces/#{space.guid}" },
          'stats' => { 'href' => "#{link_prefix}/v3/processes/#{process.guid}/stats" },
        },
      }

      parsed_response = MultiJson.load(last_response.body)

      expect(last_response.status).to eq(202)
      expect(parsed_response).to be_a_response_like(expected_response)

      process.reload
      expect(process.instances).to eq(5)
      expect(process.memory).to eq(10)
      expect(process.disk_quota).to eq(20)

      events = VCAP::CloudController::Event.where(actor: developer.guid).all

      process_event = events.find { |e| e.type == 'audit.app.process.scale' }
      expect(process_event.values).to include({
        type:              'audit.app.process.scale',
        actee:             app_model.guid,
        actee_type:        'app',
        actee_name:        'my_app',
        actor:             developer.guid,
        actor_type:        'user',
        actor_username:    user_name,
        space_guid:        space.guid,
        organization_guid: space.organization.guid
      })
      expect(process_event.metadata).to eq({
        'process_guid' => process.guid,
        'process_type' => 'web',
        'request'      => {
          'instances'    => 5,
          'memory_in_mb' => 10,
          'disk_in_mb'   => 20
        }
      })
    end

    it 'ensures that the memory allocation is greater than existing sidecar memory allocation' do
      process = VCAP::CloudController::ProcessModel.make(
        :process,
        app:        app_model,
        type:       'web',
        instances:  2,
        memory:     1024,
        disk_quota: 1024,
        command:    'rackup',
      )

      sidecar = VCAP::CloudController::SidecarModel.make(
        name: 'my-sidecar',
        app: app_model,
        memory: 256
      )
      VCAP::CloudController::SidecarProcessTypeModel.make(sidecar: sidecar, type: process.type, app_guid: app_model.guid)

      scale_request = {
        memory_in_mb: 256,
      }

      post "/v3/processes/#{process.guid}/actions/scale", scale_request.to_json, developer_headers

      expect(last_response.status).to eq(422)
      expect(parsed_response['errors'][0]['detail']).to eq 'The requested memory allocation is not large enough to run all of your sidecar processes'

      process.reload
      expect(process.memory).to eq(1024)
    end
    context 'telemetry' do
      let(:process) {
        VCAP::CloudController::ProcessModel.make(
          :process,
          app:        app_model,
          type:       'web',
          instances:  2,
          memory:     1024,
          disk_quota: 1024,
          command:    'rackup',
        )
      }

      let(:scale_request) do {
          instances:    5,
          memory_in_mb: 10,
          disk_in_mb:   20,
        }
      end

      it 'should log the required fields when the process gets scaled' do
        Timecop.freeze do
          expected_json = {
            'telemetry-source' => 'cloud_controller_ng',
            'telemetry-time' => Time.now.to_datetime.rfc3339,
            'scale-app' => {
              'api-version' => 'v3',
              'instance-count' => 5,
              'memory-in-mb' => 10,
              'disk-in-mb' => 20,
              'process-type' => 'web',
              'app-id' => Digest::SHA256.hexdigest(process.app.guid),
              'user-id' => Digest::SHA256.hexdigest(developer.guid),
            }
          }
          expect_any_instance_of(ActiveSupport::Logger).to receive(:info).with(JSON.generate(expected_json))
          post "/v3/processes/#{process.guid}/actions/scale", scale_request.to_json, developer_headers

          expect(last_response.status).to eq(202), last_response.body
        end
      end
    end
  end

  describe 'DELETE /v3/processes/:guid/instances/:index' do
    before do
      allow_any_instance_of(VCAP::CloudController::Diego::BbsAppsClient).to receive(:stop_index)
    end
    it 'terminates a single instance of a process' do
      process = VCAP::CloudController::ProcessModel.make(:process, type: 'web', app: app_model)

      delete "/v3/processes/#{process.guid}/instances/0", nil, developer_headers

      expect(last_response.status).to eq(204)

      events        = VCAP::CloudController::Event.where(actor: developer.guid).all
      process_event = events.find { |e| e.type == 'audit.app.process.terminate_instance' }
      expect(process_event.values).to include({
        type:              'audit.app.process.terminate_instance',
        actee:             app_model.guid,
        actee_type:        'app',
        actee_name:        'my_app',
        actor:             developer.guid,
        actor_type:        'user',
        actor_username:    user_name,
        space_guid:        space.guid,
        organization_guid: space.organization.guid
      })
      expect(process_event.metadata).to eq({
        'process_guid'  => process.guid,
        'process_type'  => 'web',
        'process_index' => 0
      })
    end
  end

  describe 'GET /v3/apps/:guid/processes' do
    let!(:process1) {
      VCAP::CloudController::ProcessModel.make(
        :process,
        app:        app_model,
        type:       'web',
        instances:  2,
        memory:     1024,
        disk_quota: 1024,
        command:    'rackup',
      )
    }

    let!(:process2) {
      VCAP::CloudController::ProcessModel.make(
        :process,
        app:        app_model,
        revision:   revision2,
        type:       'worker',
        instances:  1,
        memory:     100,
        disk_quota: 200,
        command:    'start worker',
      )
    }

    let!(:process3) {
      VCAP::CloudController::ProcessModel.make(:process, app: app_model, revision: revision3)
    }

    let!(:deployment_process) {
      VCAP::CloudController::ProcessModel.make(:process, app: app_model, type: 'web-deployment', revision: deployment_revision)
    }
    let!(:revision3) { VCAP::CloudController::RevisionModel.make }
    let!(:revision2) { VCAP::CloudController::RevisionModel.make }
    let!(:deployment_revision) { VCAP::CloudController::RevisionModel.make }

    it 'returns a paginated list of processes for an app' do
      get "/v3/apps/#{app_model.guid}/processes?per_page=2", nil, developer_headers

      expected_response = {
        'pagination' => {
          'total_results' => 4,
          'total_pages'   => 2,
          'first'         => { 'href' => "#{link_prefix}/v3/apps/#{app_model.guid}/processes?page=1&per_page=2" },
          'last'          => { 'href' => "#{link_prefix}/v3/apps/#{app_model.guid}/processes?page=2&per_page=2" },
          'next'          => { 'href' => "#{link_prefix}/v3/apps/#{app_model.guid}/processes?page=2&per_page=2" },
          'previous'      => nil,
        },
        'resources' => [
          {
            'guid' => process1.guid,
            'relationships' => {
              'app' => { 'data' => { 'guid' => app_model.guid } },
              'revision' => nil,
            },
            'type'         => 'web',
            'command'      => '[PRIVATE DATA HIDDEN IN LISTS]',
            'instances'    => 2,
            'memory_in_mb' => 1024,
            'disk_in_mb'   => 1024,
            'health_check' => {
              'type' => 'port',
              'data' => {
                'timeout' => nil,
                'invocation_timeout' => nil
              }
            },
            'metadata' => { 'annotations' => {}, 'labels' => {} },
            'created_at'   => iso8601,
            'updated_at'   => iso8601,
            'links'        => {
              'self'  => { 'href' => "#{link_prefix}/v3/processes/#{process1.guid}" },
              'scale' => { 'href' => "#{link_prefix}/v3/processes/#{process1.guid}/actions/scale", 'method' => 'POST' },
              'app'   => { 'href' => "#{link_prefix}/v3/apps/#{app_model.guid}" },
              'space' => { 'href' => "#{link_prefix}/v3/spaces/#{space.guid}" },
              'stats' => { 'href' => "#{link_prefix}/v3/processes/#{process1.guid}/stats" },
            },
          },
          {
            'guid' => process2.guid,
            'relationships' => {
              'app' => { 'data' => { 'guid' => app_model.guid } },
              'revision' => {
                'data' => {
                  'guid' => revision2.guid
                }
              },
            },
            'type'         => 'worker',
            'command'      => '[PRIVATE DATA HIDDEN IN LISTS]',
            'instances'    => 1,
            'memory_in_mb' => 100,
            'disk_in_mb'   => 200,
            'health_check' => {
              'type' => 'port',
              'data' => {
                'timeout' => nil,
                'invocation_timeout' => nil
              }
            },
            'metadata' => { 'annotations' => {}, 'labels' => {} },
            'created_at'   => iso8601,
            'updated_at'   => iso8601,
            'links'        => {
              'self'  => { 'href' => "#{link_prefix}/v3/processes/#{process2.guid}" },
              'scale' => { 'href' => "#{link_prefix}/v3/processes/#{process2.guid}/actions/scale", 'method' => 'POST' },
              'app'   => { 'href' => "#{link_prefix}/v3/apps/#{app_model.guid}" },
              'space' => { 'href' => "#{link_prefix}/v3/spaces/#{space.guid}" },
              'stats' => { 'href' => "#{link_prefix}/v3/processes/#{process2.guid}/stats" },
            },
          }
        ]
      }

      parsed_response = MultiJson.load(last_response.body)

      expect(last_response.status).to eq(200)
      expect(parsed_response).to be_a_response_like(expected_response)
    end

    context 'faceted list' do
      context 'by types' do
        it 'returns only the matching processes' do
          get "/v3/apps/#{app_model.guid}/processes?per_page=2&types=worker", nil, developer_headers

          expected_pagination = {
            'total_results' => 1,
            'total_pages'   => 1,
            'first'         => { 'href' => "#{link_prefix}/v3/apps/#{app_model.guid}/processes?page=1&per_page=2&types=worker" },
            'last'          => { 'href' => "#{link_prefix}/v3/apps/#{app_model.guid}/processes?page=1&per_page=2&types=worker" },
            'next'          => nil,
            'previous'      => nil,
          }

          expect(last_response.status).to eq(200)

          parsed_response = MultiJson.load(last_response.body)

          returned_guids = parsed_response['resources'].map { |i| i['guid'] }
          expect(returned_guids).to match_array([process2.guid])
          expect(parsed_response['pagination']).to be_a_response_like(expected_pagination)
        end
      end

      context 'by guids' do
        it 'returns only the matching processes' do
          get "/v3/apps/#{app_model.guid}/processes?per_page=2&guids=#{process1.guid},#{process2.guid}", nil, developer_headers

          expected_pagination = {
            'total_results' => 2,
            'total_pages'   => 1,
            'first'         => { 'href' => "#{link_prefix}/v3/apps/#{app_model.guid}/processes?guids=#{process1.guid}%2C#{process2.guid}&page=1&per_page=2" },
            'last'          => { 'href' => "#{link_prefix}/v3/apps/#{app_model.guid}/processes?guids=#{process1.guid}%2C#{process2.guid}&page=1&per_page=2" },
            'next'          => nil,
            'previous'      => nil,
          }

          expect(last_response.status).to eq(200)

          parsed_response = MultiJson.load(last_response.body)

          returned_guids = parsed_response['resources'].map { |i| i['guid'] }
          expect(returned_guids).to match_array([process1.guid, process2.guid])
          expect(parsed_response['pagination']).to be_a_response_like(expected_pagination)
        end
      end
    end
  end

  describe 'GET /v3/apps/:guid/processes/:type' do
    it 'retrieves the process for an app with the requested type' do
      revision = VCAP::CloudController::RevisionModel.make
      process = VCAP::CloudController::ProcessModel.make(
        :process,
        app:        app_model,
        revision:   revision,
        type:       'web',
        instances:  2,
        memory:     1024,
        disk_quota: 1024,
        command:    'rackup',
      )

      get "/v3/apps/#{app_model.guid}/processes/web", nil, developer_headers

      expected_response = {
        'guid' => process.guid,
        'relationships' => {
          'app' => { 'data' => { 'guid' => app_model.guid } },
          'revision' => { 'data' => { 'guid' => revision.guid } },
        },
        'type'         => 'web',
        'command'      => 'rackup',
        'instances'    => 2,
        'memory_in_mb' => 1024,
        'disk_in_mb'   => 1024,
        'health_check' => {
          'type' => 'port',
          'data' => {
            'timeout' => nil,
            'invocation_timeout' => nil
          }
        },
        'metadata' => { 'annotations' => {}, 'labels' => {} },
        'created_at'   => iso8601,
        'updated_at'   => iso8601,
        'links'        => {
          'self'  => { 'href' => "#{link_prefix}/v3/processes/#{process.guid}" },
          'scale' => { 'href' => "#{link_prefix}/v3/processes/#{process.guid}/actions/scale", 'method' => 'POST' },
          'app'   => { 'href' => "#{link_prefix}/v3/apps/#{app_model.guid}" },
          'space' => { 'href' => "#{link_prefix}/v3/spaces/#{space.guid}" },
          'stats' => { 'href' => "#{link_prefix}/v3/processes/#{process.guid}/stats" },
        },
      }

      parsed_response = MultiJson.load(last_response.body)

      expect(last_response.status).to eq(200)
      expect(parsed_response).to be_a_response_like(expected_response)
    end

    it 'redacts information for auditors' do
      VCAP::CloudController::ProcessModel.make(:process, app: app_model, type: 'web', command: 'rackup')

      auditor = VCAP::CloudController::User.make
      space.organization.add_user(auditor)
      space.add_auditor(auditor)

      get "/v3/apps/#{app_model.guid}/processes/web", nil, headers_for(auditor)

      parsed_response = MultiJson.load(last_response.body)

      expect(last_response.status).to eq(200)
      expect(parsed_response['command']).to eq('[PRIVATE DATA HIDDEN]')
    end
  end

  describe 'PATCH /v3/apps/:guid/processes/:type' do
    it 'updates the process' do
      process = VCAP::CloudController::ProcessModel.make(
        :process,
        app:                  app_model,
        type:                 'web',
        instances:            2,
        memory:               1024,
        disk_quota:           1024,
        command:              'rackup',
        ports:                [4444, 5555],
        health_check_type:    'port',
        health_check_timeout: 10
      )

      update_request = {
        command:      'new command',
        health_check: {
          type: 'http',
          data: {
            timeout: 20,
            endpoint: '/healthcheck'
          }
        },
        metadata: metadata,
      }.to_json

      patch "/v3/apps/#{app_model.guid}/processes/web", update_request, developer_headers.merge('CONTENT_TYPE' => 'application/json')

      expected_response = {
        'guid' => process.guid,
        'relationships' => {
          'app' => { 'data' => { 'guid' => app_model.guid } },
          'revision' => nil,
        },
        'type'         => 'web',
        'command'      => 'new command',
        'instances'    => 2,
        'memory_in_mb' => 1024,
        'disk_in_mb'   => 1024,
        'health_check' => {
          'type' => 'http',
          'data' => {
            'timeout' => 20,
            'endpoint' => '/healthcheck',
            'invocation_timeout' => nil
          }
        },
        'created_at'   => iso8601,
        'updated_at'   => iso8601,
        'links'        => {
          'self'  => { 'href' => "#{link_prefix}/v3/processes/#{process.guid}" },
          'scale' => { 'href' => "#{link_prefix}/v3/processes/#{process.guid}/actions/scale", 'method' => 'POST' },
          'app'   => { 'href' => "#{link_prefix}/v3/apps/#{app_model.guid}" },
          'space' => { 'href' => "#{link_prefix}/v3/spaces/#{space.guid}" },
          'stats' => { 'href' => "#{link_prefix}/v3/processes/#{process.guid}/stats" },
        },
        'metadata' => {
          'labels' => {
            'release' => 'stable',
            'seriouseats.com/potato' => 'mashed',
          },
          'annotations' => { 'checksum' => 'SHA' },
        }
      }

      parsed_response = MultiJson.load(last_response.body)

      expect(last_response.status).to eq(200)
      expect(parsed_response).to be_a_response_like(expected_response)

      process.reload
      expect(process.command).to eq('new command')
      expect(process.health_check_type).to eq('http')
      expect(process.health_check_timeout).to eq(20)
      expect(process.health_check_http_endpoint).to eq('/healthcheck')

      event = VCAP::CloudController::Event.last
      expect(event.values).to include({
        type:              'audit.app.process.update',
        actee:             app_model.guid,
        actee_type:        'app',
        actee_name:        'my_app',
        actor:             developer.guid,
        actor_type:        'user',
        actor_username:    user_name,
        space_guid:        space.guid,
        organization_guid: space.organization.guid
      })
      expect(event.metadata).to eq({
        'process_guid' => process.guid,
        'process_type' => 'web',
        'request'      => {
          'command'      => '[PRIVATE DATA HIDDEN]',
          'health_check' => {
            'type' => 'http',
            'data' => {
              'timeout' => 20,
              'endpoint' => '/healthcheck',
            }
          },
          'metadata' => {
          'labels' => {
            'release' => 'stable',
            'seriouseats.com/potato' => 'mashed',
          },
          'annotations' => { 'checksum' => 'SHA' },
        },
        }
      })
    end
  end

  describe 'POST /v3/apps/:guid/processes/:type/actions/scale' do
    let!(:process) { VCAP::CloudController::ProcessModel.make(
      :process,
      app:        app_model,
      type:       'web',
      instances:  2,
      memory:     1024,
      disk_quota: 1024,
      command:    'rackup',
    )
    }
    let(:scale_request) do {
      instances:    5,
      memory_in_mb: 10,
      disk_in_mb:   20,
    }
    end
    it 'scales the process belonging to an app' do
      post "/v3/apps/#{app_model.guid}/processes/web/actions/scale", scale_request.to_json, developer_headers
      expected_response = {
        'guid'         => process.guid,
        'type'         => 'web',

        'relationships' => {
          'app' => { 'data' => { 'guid' => app_model.guid } },
          'revision' => nil,
        },
        'command'      => 'rackup',
        'instances'    => 5,
        'memory_in_mb' => 10,
        'disk_in_mb'   => 20,
        'health_check' => {
          'type' => 'port',
          'data' => {
            'timeout' => nil,
            'invocation_timeout' => nil
          }
        },
        'metadata' => { 'annotations' => {}, 'labels' => {} },
        'created_at'   => iso8601,
        'updated_at'   => iso8601,
        'links'        => {
          'self'  => { 'href' => "#{link_prefix}/v3/processes/#{process.guid}" },
          'scale' => { 'href' => "#{link_prefix}/v3/processes/#{process.guid}/actions/scale", 'method' => 'POST' },
          'app'   => { 'href' => "#{link_prefix}/v3/apps/#{app_model.guid}" },
          'space' => { 'href' => "#{link_prefix}/v3/spaces/#{space.guid}" },
          'stats' => { 'href' => "#{link_prefix}/v3/processes/#{process.guid}/stats" },
        },
      }

      parsed_response = MultiJson.load(last_response.body)

      expect(last_response.status).to eq(202)
      expect(parsed_response).to be_a_response_like(expected_response)

      process.reload
      expect(process.instances).to eq(5)
      expect(process.memory).to eq(10)
      expect(process.disk_quota).to eq(20)

      events = VCAP::CloudController::Event.where(actor: developer.guid).all

      process_event = events.find { |e| e.type == 'audit.app.process.scale' }
      expect(process_event.values).to include({
        type:              'audit.app.process.scale',
        actee:             app_model.guid,
        actee_type:        'app',
        actee_name:        'my_app',
        actor:             developer.guid,
        actor_type:        'user',
        actor_username:    user_name,
        space_guid:        space.guid,
        organization_guid: space.organization.guid
      })
      expect(process_event.metadata).to eq({
        'process_guid' => process.guid,
        'process_type' => 'web',
        'request'      => {
          'instances'    => 5,
          'memory_in_mb' => 10,
          'disk_in_mb'   => 20
        }
      })
    end

    context 'telemetry' do
      it 'should log the required fields when the process gets scaled' do
        Timecop.freeze do
          expected_json = {
            'telemetry-source' => 'cloud_controller_ng',
            'telemetry-time' => Time.now.to_datetime.rfc3339,
            'scale-app' => {
              'api-version' => 'v3',
              'instance-count' => 5,
              'memory-in-mb' => 10,
              'disk-in-mb' => 20,
              'process-type' => 'web',
              'app-id' => Digest::SHA256.hexdigest(app_model.guid),
              'user-id' => Digest::SHA256.hexdigest(developer.guid),
            }
          }
          expect_any_instance_of(ActiveSupport::Logger).to receive(:info).with(JSON.generate(expected_json))

          post "/v3/apps/#{app_model.guid}/processes/web/actions/scale", scale_request.to_json, developer_headers

          expect(last_response.status).to eq(202), last_response.body
        end
      end
    end
  end

  describe 'DELETE /v3/apps/:guid/processes/:type/instances/:index' do
    before do
      allow_any_instance_of(VCAP::CloudController::Diego::BbsAppsClient).to receive(:stop_index)
    end
    it 'terminates a single instance of a process belonging to an app' do
      process = VCAP::CloudController::ProcessModel.make(:process, type: 'web', app: app_model)

      delete "/v3/apps/#{app_model.guid}/processes/web/instances/0", nil, developer_headers

      expect(last_response.status).to eq(204)

      events        = VCAP::CloudController::Event.where(actor: developer.guid).all
      process_event = events.find { |e| e.type == 'audit.app.process.terminate_instance' }
      expect(process_event.values).to include({
        type:              'audit.app.process.terminate_instance',
        actee:             app_model.guid,
        actee_type:        'app',
        actee_name:        'my_app',
        actor:             developer.guid,
        actor_type:        'user',
        actor_username:    user_name,
        space_guid:        space.guid,
        organization_guid: space.organization.guid
      })
      expect(process_event.metadata).to eq({
        'process_guid'  => process.guid,
        'process_type'  => 'web',
        'process_index' => 0
      })
    end
  end
end
