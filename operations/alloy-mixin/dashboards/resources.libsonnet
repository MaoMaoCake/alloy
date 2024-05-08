local dashboard = import './utils/dashboard.jsonnet';
local panel = import './utils/panel.jsonnet';
local filename = 'alloy-resources.json';

local pointsMixin = {
  fieldConfig+: {
    defaults+: {
      custom: {
        drawStyle: 'points',
        pointSize: 3,
      },
    },
  },

};

local stackedPanelMixin = {
  fieldConfig+: {
    defaults+: {
      custom+: {
        fillOpacity: 30,
        gradientMode: 'none',
        stacking: { mode: 'normal' },
      },
    },
  },
};

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
    dashboard.new(name='Alloy / Resources', tag=$._config.dashboardTag) +
    dashboard.withDashboardsLink(tag=$._config.dashboardTag) +
    dashboard.withUID(std.md5(filename)) +
    dashboard.withTemplateVariablesMixin(templateVariables) +
    // TODO(@tpaschalis) Make the annotation optional.
    dashboard.withAnnotations([
      dashboard.newLokiAnnotation('Deployments', '{cluster="$cluster", container="kube-diff-logger"} | json | namespace_extracted="alloy" | name_extracted=~"alloy.*"', 'rgba(0, 211, 255, 1)'),
    ]) +
    dashboard.withPanelsMixin([
      // CPU usage
      (
        panel.new(title='CPU usage', type='timeseries') +
        panel.withUnit('percentunit') +
        panel.withDescription(|||
          CPU usage of the Alloy process relative to 1 CPU core.

          For example, 100% means using one entire CPU core.
        |||) +
        panel.withPosition({ x: 0, y: 0, w: 12, h: 8 }) +
        panel.withQueries([
          panel.newQuery(
            expr='rate(alloy_resources_process_cpu_seconds_total{' + $._config.instanceSelector + '}[$__rate_interval])',
            legendFormat='{{instance}}'
          ),
        ])
      ),

      // Memory (RSS)
      (
        panel.new(title='Memory (RSS)', type='timeseries') +
        panel.withUnit('decbytes') +
        panel.withDescription(|||
          Resident memory size of the Alloy process.
        |||) +
        panel.withPosition({ x: 12, y: 0, w: 12, h: 8 }) +
        panel.withQueries([
          panel.newQuery(
            expr='alloy_resources_process_resident_memory_bytes{' + $._config.instanceSelector + '}',
            legendFormat='{{instance}}'
          ),
        ])
      ),

      // GCs
      (
        panel.new(title='Garbage collections', type='timeseries') +
        pointsMixin +
        panel.withUnit('ops') +
        panel.withDescription(|||
          Rate at which the Alloy process performs garbage collections.
        |||) +
        panel.withPosition({ x: 0, y: 8, w: 8, h: 8 }) +
        panel.withQueries([
          panel.newQuery(
            // Lots of programs export go_goroutines so we ignore anything that
            // doesn't also have an Alloy-specific metric (i.e.,
            // alloy_build_info).
            expr=
              'rate(go_gc_duration_seconds_count{' + $._config.instanceSelector + '}[5m])
              and on(instance)
              alloy_build_info{' + $._config.instanceSelector + '}'
            ,
            legendFormat='{{instance}}'
          ),
        ])
      ),

      // Goroutines
      (
        panel.new(title='Goroutines', type='timeseries') +
        panel.withUnit('none') +
        panel.withDescription(|||
          Number of goroutines which are running in parallel. An infinitely
          growing number of these indicates a goroutine leak.
        |||) +
        panel.withPosition({ x: 8, y: 8, w: 8, h: 8 }) +
        panel.withQueries([
          panel.newQuery(
            // Lots of programs export go_goroutines so we ignore anything that
            // doesn't also have an Alloy-specific metric (i.e.,
            // alloy_build_info).
            expr=
              'go_goroutines{' + $._config.instanceSelector + '}
              and on(instance)
              alloy_build_info{' + $._config.instanceSelector + '}'
            ,
            legendFormat='{{instance}}'
          ),
        ])
      ),

      // Memory (Go heap inuse)
      (
        panel.new(title='Memory (heap inuse)', type='timeseries') +
        panel.withUnit('decbytes') +
        panel.withDescription(|||
          Heap memory currently in use by the Alloy process.
        |||) +
        panel.withPosition({ x: 16, y: 8, w: 8, h: 8 }) +
        panel.withQueries([
          panel.newQuery(
            // Lots of programs export go_memstats_heap_inuse_bytes so we ignore
            // anything that doesn't also have an Alloy-specific metric
            // (i.e., alloy_build_info).
            expr=
              'go_memstats_heap_inuse_bytes{' + $._config.instanceSelector + '}
              and on(instance)
              alloy_build_info{' + $._config.instanceSelector + '}'
            ,
            legendFormat='{{instance}}'
          ),
        ])
      ),

      // Network RX
      (
        panel.new(title='Network receive bandwidth', type='timeseries') +
        stackedPanelMixin +
        panel.withUnit('Bps') +
        panel.withDescription(|||
          Rate of data received across all network interfaces for the machine
          Alloy is running on.

          Data shown here is across all running processes and not exclusive to
          the running Alloy process.
        |||) +
        panel.withPosition({ x: 0, y: 16, w: 12, h: 8 }) +
        panel.withQueries([
          panel.newQuery(
            expr=
              'rate(alloy_resources_machine_rx_bytes_total{' + $._config.instanceSelector + '}[$__rate_interval])'
            ,
            legendFormat='{{instance}}'
          ),
        ])
      ),

      // Network RX
      (
        panel.new(title='Network send bandwidth', type='timeseries') +
        stackedPanelMixin +
        panel.withUnit('Bps') +
        panel.withDescription(|||
          Rate of data sent across all network interfaces for the machine
          Alloy is running on.

          Data shown here is across all running processes and not exclusive to
          the running Alloy process.
        |||) +
        panel.withPosition({ x: 12, y: 16, w: 12, h: 8 }) +
        panel.withQueries([
          panel.newQuery(
            expr=
              'rate(alloy_resources_machine_tx_bytes_total{' + $._config.instanceSelector + '}[$__rate_interval])'
            ,
            legendFormat='{{instance}}'
          ),
        ])
      ),
    ]),
}
