local dashboard = import './utils/dashboard.jsonnet';
local panel = import './utils/panel.jsonnet';
local filename = 'alloy-cluster-node.json';

{
  local templateVariables = 
    if $._config.enableK8sCluster then
      [
        dashboard.newMultiTemplateVariable('job', 'label_values(alloy_component_controller_running_components, job)'),
        dashboard.newTemplateVariable('cluster', 'label_values(alloy_component_controller_running_components{job=~"$job"}, cluster)'),
        dashboard.newTemplateVariable('namespace', 'label_values(alloy_component_controller_running_components{job=~"$job", cluster=~"$cluster"}, namespace)'),
        dashboard.newMultiTemplateVariable('instance', 'label_values(alloy_component_controller_running_components{job=~"$job", cluster=~"$cluster", namespace=~"$namespace"}, instance)'),
      ]
    else
      [
        dashboard.newMultiTemplateVariable('job', 'label_values(alloy_component_controller_running_components, job)'),
        dashboard.newMultiTemplateVariable('instance', 'label_values(alloy_component_controller_running_components{job=~"$job"}, instance)'),
      ],

  [filename]:
    dashboard.new(name='Alloy / Cluster Node', tag=$._config.dashboardTag) +
    dashboard.withDocsLink(
      url='https://grafana.com/docs/alloy/latest/reference/cli/run/#clustered-mode',
      desc='Clustering documentation',
    ) +
    dashboard.withDashboardsLink(tag=$._config.dashboardTag) +
    dashboard.withUID(std.md5(filename)) +
    dashboard.withTemplateVariablesMixin(templateVariables) +
    // TODO(@tpaschalis) Make the annotation optional.
    dashboard.withAnnotations([
      dashboard.newLokiAnnotation('Deployments', '{cluster="$cluster", container="kube-diff-logger"} | json | namespace_extracted="alloy" | name_extracted=~"alloy.*"', 'rgba(0, 211, 255, 1)'),
    ]) +
    dashboard.withPanelsMixin([
      // Node Info row
      (
        panel.new('Node Info', 'row') +
        panel.withPosition({ h: 1, w: 24, x: 0, y: 0 })
      ),
      // Node Info
      (
        panel.new('Node Info', 'table') +
        panel.withDescription(|||
          Information about a specific cluster node.

          * Lamport clock time: The observed Lamport time on the specific node's clock used to provide partial ordering around gossip messages. Nodes should ideally be observing roughly the same time, meaning they are up-to-date on the cluster state. If a node is falling behind, it means that it has not recently processed the same number of messages and may have an outdated view of its peers.

          * Internal cluster state observers: The number of Observer functions that are registered to run whenever the node detects a cluster change.

          * Gossip health score: A health score assigned to this node by the memberlist implementation. The lower, the better.

          * Gossip protocol version: The protocol version used by nodes to communicate with one another. It should match across all nodes.
        |||) +
        panel.withPosition({ x: 0, y: 1, w: 12, h: 8 }) +
        panel.withQueries([
          panel.newNamedInstantQuery(
            expr='sum(cluster_node_lamport_time{' + $._config.instanceSelector + '})',
            refId='Lamport clock time',
            format='table',
          ),
          panel.newNamedInstantQuery(
            expr='sum(cluster_node_update_observers{' + $._config.instanceSelector + '})',
            refId='Internal cluster state observers',
            format='table',
          ),
          panel.newNamedInstantQuery(
            expr='sum(cluster_node_gossip_health_score{' + $._config.instanceSelector + '})',
            refId='Gossip health score',
            format='table',
          ),
          panel.newNamedInstantQuery(
            expr='sum(cluster_node_gossip_proto_version{' + $._config.instanceSelector + '})',
            refId='Gossip protocol version',
            format='table',
          ),
        ]) +
        panel.withTransformations([
          {
            id: 'renameByRegex',
            options: {
              regex: 'Value #(.*)',
              renamePattern: '$1',
            },
          },
          {
            id: 'reduce',
            options: {},
          },
          {
            id: 'organize',
            options: {
              excludeByName: {},
              indexByName: {},
              renameByName: {
                Field: 'Metric',
                Max: 'Value',
              },
            },
          },
        ])
      ),
      // Gossip ops/sec
      (
        panel.new('Gossip ops/s', 'timeseries') +
        panel.withPosition({ x: 12, y: 1, w: 12, h: 8 }) +
        panel.withQueries([
          panel.newQuery(
            expr='rate(cluster_node_gossip_received_events_total{' + $._config.instanceSelector + '}[$__rate_interval])',
            legendFormat='{{event}}'
          ),
        ])
      ),
      // Known peers
      (
        panel.new('Known peers', 'stat') +
        panel.withDescription(|||
          Known peers to the node (including the local node).
        |||) +
        panel.withPosition({ x: 0, y: 9, w: 12, h: 8 }) +
        panel.withQueries([
          panel.newQuery(
            expr='sum(cluster_node_peers{' + $._config.instanceSelector + '})',
          ),
        ]) +
        panel.withUnit('suffix:peers')
      ),
      // Peers by state
      (
        panel.new('Peers by state', 'timeseries') +
        panel.withDescription(|||
          Known peers to the node by state (including the local node).
        |||) +
        panel.withPosition({ x: 12, y: 9, w: 12, h: 8 }) +
        panel.withQueries([
          panel.newQuery(
            expr='cluster_node_peers{' + $._config.instanceSelector + '}',
            legendFormat='{{state}}',
          ),
        ]) +
        panel.withUnit('suffix:nodes')
      ),
      // Gossip Transport row
      (
        panel.new('Gossip Transport', 'row') +
        panel.withPosition({ h: 1, w: 24, x: 0, y: 17 })
      ),
      // Transport bandwidth
      (
        panel.new('Transport bandwidth', 'timeseries') +
        panel.withPosition({
          h: 8,
          w: 8,
          x: 0,
          y: 18,
        }) +
        panel.withQueries([
          panel.newQuery(
            expr='rate(cluster_transport_rx_bytes_total{' + $._config.instanceSelector + '}[$__rate_interval])',
            legendFormat='rx',
          ),
          panel.newQuery(
            expr='-1 * rate(cluster_transport_tx_bytes_total{' + $._config.instanceSelector + '}[$__rate_interval])',
            legendFormat='tx',
          ),
        ]) +
        panel.withCenteredAxis() +
        panel.withUnit('Bps')
      ),
      // Packet write success rate
      (
        panel.new('Packet write success rate', 'timeseries') +
        panel.withPosition({
          h: 8,
          w: 8,
          x: 8,
          y: 18,
        }) +
        panel.withQueries([
          panel.newQuery(
            expr=
              '1 - (
              rate(cluster_transport_tx_packets_failed_total{' + $._config.instanceSelector + '}[$__rate_interval]) /
              rate(cluster_transport_tx_packets_total{' + $._config.instanceSelector + '}[$__rate_interval])
              )',
            legendFormat='Tx success %',
          ),
          panel.newQuery(
            expr=
              '1 - (
                rate(cluster_transport_rx_packets_failed_total{' + $._config.instanceSelector + '}[$__rate_interval]) /
                rate(cluster_transport_rx_packets_total{' + $._config.instanceSelector + '}[$__rate_interval])
                )',
            legendFormat='Rx success %',
          ),
        ]) +
        panel.withUnit('percentunit')
      ),
      // Pending packet queue
      (
        panel.new('Pending packet queue', 'timeseries') +
        panel.withDescription(|||
          The number of packets enqueued currently to be decoded or encoded and sent during communication with other nodes.

          The incoming and outgoing packet queue should be as empty as possible; a growing queue means that Alloy cannot keep up with the number of messages required to have all nodes informed of cluster changes, and the nodes may not converge in a timely fashion.
        |||) +
        panel.withPosition({
          h: 8,
          w: 8,
          x: 16,
          y: 18,
        }) +
        panel.withQueries([
          panel.newQuery(
            expr='cluster_transport_tx_packet_queue_length{' + $._config.instanceSelector + '}',
            legendFormat='tx queue',
          ),
          panel.newQuery(
            expr='cluster_transport_rx_packet_queue_length{' + $._config.instanceSelector + '}',
            legendFormat='rx queue',
          ),
        ]) +
        panel.withUnit('pkts')
      ),
      // Stream bandwidth
      (
        panel.new('Stream bandwidth', 'timeseries') +
        panel.withPosition({
          h: 8,
          w: 8,
          x: 0,
          y: 26,
        }) +
        panel.withQueries([
          panel.newQuery(
            expr='rate(cluster_transport_stream_rx_bytes_total{' + $._config.instanceSelector + '}[$__rate_interval])',
            legendFormat='rx',
          ),
          panel.newQuery(
            expr='-1 * rate(cluster_transport_stream_tx_bytes_total{' + $._config.instanceSelector + '}[$__rate_interval])',
            legendFormat='tx',
          ),
        ]) +
        panel.withCenteredAxis() +
        panel.withUnit('Bps')
      ),
      // Stream write success rate
      (
        panel.new('Stream write success rate', 'timeseries') +
        panel.withPosition({
          h: 8,
          w: 8,
          x: 8,
          y: 26,
        }) +
        panel.withQueries([
          panel.newQuery(
            expr=
              '1 - (
                rate(cluster_transport_stream_tx_packets_failed_total{' + $._config.instanceSelector + '}[$__rate_interval]) /
                rate(cluster_transport_stream_tx_packets_total{' + $._config.instanceSelector + '}[$__rate_interval])
                )',
            legendFormat='Tx success %'
          ),
          panel.newQuery(
            expr=
              '1 - (
                rate(cluster_transport_stream_rx_packets_failed_total{' + $._config.instanceSelector + '}[$__rate_interval]) /
                rate(cluster_transport_stream_rx_packets_total{' + $._config.instanceSelector + '}[$__rate_interval])
                )',
            legendFormat='Rx success %'
          ),
        ]) +
        panel.withUnit('percentunit')
      ),
      // Open transport streams
      (
        panel.new('Open transport streams', 'timeseries') +
        panel.withDescription(|||
          The number of open connections from this node to its peers.

          Each node picks up a subset of its peers to continuously gossip messages around cluster status using streaming HTTP/2 connections. This panel can be used to detect networking failures that result in cluster communication being disrupted and convergence taking longer than expected or outright failing.
        |||) +
        panel.withPosition({
          h: 8,
          w: 8,
          x: 16,
          y: 26,
        }) +
        panel.withQueries([
          panel.newQuery(
            expr='cluster_transport_streams{' + $._config.instanceSelector + '}',
            legendFormat='Open streams'
          ),
        ])
      ),
    ]),
}
