# frozen_string_literal: true

RSpec.describe Kumonos::Envoy do
  let(:definition) do
    YAML.load_file(File.expand_path('../example/envoy_config.yml', __dir__))
  end
  let(:cluster) { 'test-cluster' }
  let(:node) { 'test-node' }

  specify 'generate' do
    config = Kumonos::Envoy.generate(
      definition,
      cluster: cluster,
      node: node
    )
    out = JSON.dump(config)
    expect(out).to be_json_as(
      admin: {
        access_log_path: '/dev/stdout',
        address: {
          socket_address: { address: '0.0.0.0', port_value: 9901 }
        }
      },
      stats_sinks: [
        {
          name: 'envoy.dog_statsd',
          config: {
            address: {
              socket_address: {
                protocol: 'UDP',
                address: 'statsd-exporter',
                port_value: 9125
              }
            }
          }
        }
      ],
      stats_config: {
        use_all_default_tags: true,
        stats_tags: [
          { tag_name: 'service-cluster', fixed_value: cluster },
          { tag_name: 'service-node', fixed_value: node }
        ]
      },
      static_resources: {
        listeners: [
          {
            name: 'egress',
            address: {
              socket_address: { address: '0.0.0.0', port_value: 9211 }
            },
            filter_chains: [
              {
                filters: [
                  {
                    name: 'envoy.http_connection_manager',
                    config: {
                      codec_type: 'AUTO',
                      stat_prefix: 'egress_http',
                      access_log: [
                        {
                          name: 'envoy.file_access_log',
                          config: {
                            path: '/dev/stdout'
                          }
                        }
                      ],
                      rds: {
                        config_source: {
                          api_config_source: {
                            cluster_names: ['nginx'],
                            refresh_delay: {
                              seconds: 10
                            }
                          }
                        },
                        route_config_name: 'default'
                      },
                      http_filters: [{ name: 'envoy.router' }]
                    }
                  }
                ]
              }
            ]
          }
        ],
        clusters: [
          {
            name: 'nginx',
            connect_timeout: {
              seconds: 0,
              nanos: 100_000_000
            },
            type: 'STRICT_DNS',
            dns_lookup_family: 'V4_ONLY',
            lb_policy: 'ROUND_ROBIN',
            hosts: [
              { socket_address: { address: 'nginx', port_value: 80 } }
            ]
          },
          {
            name: 'sds',
            connect_timeout: {
              seconds: 1,
              nanos: 500_000_000
            },
            type: 'STRICT_DNS',
            dns_lookup_family: 'V4_ONLY',
            lb_policy: 'ROUND_ROBIN',
            hosts: [
              { socket_address: { address: 'sds', port_value: 8080 } }
            ]
          }
        ]
      },
      dynamic_resources: {
        cds_config: {
          api_config_source: {
            cluster_names: ['nginx'],
            refresh_delay: {
              seconds: 10
            }
          }
        },
        deprecated_v1: {
          sds_config: {
            api_config_source: {
              cluster_names: ['sds'],
              refresh_delay: { seconds: 1.0 }
            }
          }
        }
      }
    )
  end

  specify '.generate with ds with TLS' do
    definition['discovery_service']['tls'] = true
    out = Kumonos::Envoy.generate(definition, cluster: cluster, node: node)
    ds_cluster = out.fetch(:static_resources).fetch(:clusters)[0]
    expect(JSON.dump(ds_cluster)).to be_json_as(
      name: 'nginx',
      type: 'STRICT_DNS',
      dns_lookup_family: 'V4_ONLY',
      tls_context: {},
      connect_timeout: {
        seconds: 0,
        nanos: 100_000_000
      },
      lb_policy: 'ROUND_ROBIN',
      hosts: [
        { socket_address: { address: 'nginx', port_value: 80 } }
      ]
    )
  end

  specify '.generate without statsd' do
    definition.delete('statsd')
    out = Kumonos::Envoy.generate(definition, cluster: cluster, node: node)
    expect(out).not_to have_key(:stats_sinks)
    expect(out).not_to have_key(:stats_config)
  end

  specify '.generate with fault injection' do
    runtime_configuration = {
      symlink_root: '/srv/runtime/current',
      subdirectory: 'envoy',
      override_subdirectory: 'envoy_override'
    }
    definition['runtime'] = runtime_configuration

    additional_http_filters_configuration = [
      { name: 'envoy.fault' }
    ]
    definition['listener']['additional_http_filters'] = additional_http_filters_configuration

    out = Kumonos::Envoy.generate(definition, cluster: cluster, node: node)
    runtime = out.fetch(:runtime)
    http_filters = out.fetch(:static_resources).fetch(:listeners)[0].fetch(:filter_chains)[0].fetch(:filters)[0].fetch(:config).fetch(:http_filters)

    expect(JSON.dump(runtime)).to be_json_as(runtime_configuration)
    expect(JSON.dump(http_filters)).to be_json_as(additional_http_filters_configuration + Kumonos::Envoy::DEFAULT_HTTP_FILTERS)
  end
end
