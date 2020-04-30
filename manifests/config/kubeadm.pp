# Class kubernetes config kubeadm, populates kubeadm config file with params to bootstrap cluster
class kubernetes::config::kubeadm (
  String $config_file = $kubernetes::config_file,
  String $controller_address = $kubernetes::controller_address,
  String $dns_domain = $kubernetes::dns_domain,
  Boolean $manage_etcd = $kubernetes::manage_etcd,
  Boolean $delegated_pki = $kubernetes::delegated_pki,
  String $etcd_install_method = $kubernetes::etcd_install_method,
  String $kubernetes_version  = $kubernetes::kubernetes_version,
  String $kubernetes_cluster_name  = $kubernetes::kubernetes_cluster_name,
  Optional[String] $etcd_ca_key = $kubernetes::etcd_ca_key,
  Optional[String] $etcd_ca_crt = $kubernetes::etcd_ca_crt,
  Optional[String] $etcdclient_key = $kubernetes::etcdclient_key,
  Optional[String] $etcdclient_crt = $kubernetes::etcdclient_crt,
  Optional[String] $etcdserver_crt = $kubernetes::etcdserver_crt,
  Optional[String] $etcdserver_key = $kubernetes::etcdserver_key,
  Optional[String] $etcdpeer_crt = $kubernetes::etcdpeer_crt,
  Optional[String] $etcdpeer_key = $kubernetes::etcdpeer_key,
  Array $etcd_peers = $kubernetes::etcd_peers,
  String $etcd_hostname = $kubernetes::etcd_hostname,
  String $etcd_ip = $kubernetes::etcd_ip,
  String $cni_pod_cidr = $kubernetes::cni_pod_cidr,
  Integer $kube_api_bind_port = $kubernetes::kube_api_bind_port,
  String $kube_api_advertise_address = $kubernetes::kube_api_advertise_address,
  Optional[String] $etcd_initial_cluster = $kubernetes::etcd_initial_cluster,
  Optional[String] $etcd_discovery_srv = $kubernetes::etcd_discovery_srv,
  String $etcd_initial_cluster_state = $kubernetes::etcd_initial_cluster_state,
  String $etcd_compaction_method = $kubernetes::etcd_compaction_method,
  Variant[Integer,String] $etcd_compaction_retention = $kubernetes::etcd_compaction_retention,
  Integer $api_server_count = $kubernetes::api_server_count,
  String $etcd_version = $kubernetes::etcd_version,
  Integer $etcd_max_wals = $kubernetes::etcd_max_wals,
  String $token = $kubernetes::token,
  String $ttl_duration = $kubernetes::ttl_duration,
  String $discovery_token_hash = $kubernetes::discovery_token_hash,
  Optional[String] $kubernetes_ca_crt = $kubernetes::kubernetes_ca_crt,
  Optional[String] $kubernetes_ca_key = $kubernetes::kubernetes_ca_key,
  Optional[String] $kubernetes_front_proxy_ca_crt = $kubernetes::kubernetes_front_proxy_ca_crt,
  Optional[String] $kubernetes_front_proxy_ca_key = $kubernetes::kubernetes_front_proxy_ca_key,
  String $container_runtime = $kubernetes::container_runtime,
  String $sa_pub = $kubernetes::sa_pub,
  String $sa_key = $kubernetes::sa_key,
  Optional[Array] $apiserver_cert_extra_sans = $kubernetes::apiserver_cert_extra_sans,
  Optional[Array] $apiserver_extra_arguments = $kubernetes::apiserver_extra_arguments,
  Optional[Array] $controllermanager_extra_arguments = $kubernetes::controllermanager_extra_arguments,
  Optional[Array] $kubelet_extra_arguments = $kubernetes::kubelet_extra_arguments,
  String $service_cidr = $kubernetes::service_cidr,
  String $node_name = $kubernetes::node_name,
  Optional[String] $cloud_provider = $kubernetes::cloud_provider,
  Optional[String] $cloud_config = $kubernetes::cloud_config,
  Optional[Hash] $apiserver_extra_volumes = $kubernetes::apiserver_extra_volumes,
  Optional[Hash] $controllermanager_extra_volumes = $kubernetes::controllermanager_extra_volumes,
  Optional[Hash] $kubeadm_extra_config = $kubernetes::kubeadm_extra_config,
  Optional[Hash] $kubelet_extra_config = $kubernetes::kubelet_extra_config,
  String $image_repository = $kubernetes::image_repository,
  String $cgroup_driver = $kubernetes::cgroup_driver,
  String $proxy_mode = $kubernetes::proxy_mode,
  Stdlib::IP::Address $metrics_bind_address = $kubernetes::metrics_bind_address,
) {

  if !($proxy_mode in ['', 'userspace', 'iptables', 'ipvs', 'kernelspace']) {
    fail('Invalid kube-proxy mode! Must be one of "", userspace, iptables, ipvs, kernelspace.')
  }

  if !($etcd_discovery_srv or $etcd_initial_cluster) {
    fail('One of $etcd_discovery_srv or $etcd_initial_cluster variables must be defined')
  }

  $kube_dirs = ['/etc/kubernetes','/etc/kubernetes/manifests','/etc/kubernetes/pki','/etc/kubernetes/pki/etcd']
  $etcd = ['ca.crt', 'ca.key', 'client.crt', 'client.key','peer.crt', 'peer.key', 'server.crt', 'server.key']
  $pki = ['ca.crt','ca.key','front-proxy-ca.crt','front-proxy-ca.key','sa.pub','sa.key']
  $kube_dirs.each | String $dir |  {
    file  { $dir :
      ensure  => directory,
      mode    => '0600',
      recurse => true,
    }
  }

  if $manage_etcd {
    if !$delegated_pki {
      $etcd.each | String $etcd_files | {
        file { "/etc/kubernetes/pki/etcd/${etcd_files}":
          ensure  => present,
          content => template("kubernetes/etcd/${etcd_files}.erb"),
          mode    => '0600',
        }
      }
    }
    if $etcd_install_method == 'wget' {
      file { '/etc/systemd/system/etcd.service':
        ensure  => present,
        content => template('kubernetes/etcd/etcd.service.erb'),
      }
    } else {
      file { '/etc/default/etcd':
        ensure  => present,
        content => template('kubernetes/etcd/etcd.erb'),
      }
    }
  }

  if !$delegated_pki {
    $pki.each | String $pki_files | {
      file {"/etc/kubernetes/pki/${pki_files}":
        ensure  => present,
        content => template("kubernetes/pki/${pki_files}.erb"),
        mode    => '0600',
      }
    }
  }

  # The alpha1 schema puts Kubelet configuration in a different place.
  $kubelet_extra_config_alpha1 = {
    'kubeletConfiguration' => {
      'baseConfig' => $kubelet_extra_config,
    },
  }

  # Need to merge the cloud configuration parameters into extra_arguments
  if $cloud_provider {
    $cloud_args = $cloud_config ? {
      undef   => ["cloud-provider: ${cloud_provider}"],
      default => ["cloud-provider: ${cloud_provider}", "cloud-config: ${cloud_config}"],
    }
    $apiserver_merged_extra_arguments = concat($apiserver_extra_arguments, $cloud_args)
    $controllermanager_merged_extra_arguments = concat($controllermanager_extra_arguments, $cloud_args)

    # could check against Kubernetes 1.10 here, but that uses alpha1 config which doesn't have these options
    if $cloud_config {
      # The cloud config must be mounted into the apiserver and controllermanager containers
      $cloud_volume = {
        'cloud' => {
          hostPath  => $cloud_config,
          mountPath => $cloud_config,
        },
      }
      if has_key($apiserver_extra_volumes, 'cloud') or has_key($controllermanager_extra_volumes, 'cloud') {
        fail('Cannot use "cloud" as volume name')
      }

      $apiserver_merged_extra_volumes = merge($apiserver_extra_volumes, $cloud_volume)
      $controllermanager_merged_extra_volumes = merge($controllermanager_extra_volumes, $cloud_volume)
    } else {
      $apiserver_merged_extra_volumes = $apiserver_extra_volumes
      $controllermanager_merged_extra_volumes = $controllermanager_extra_volumes
    }
  } else {
    $apiserver_merged_extra_arguments = $apiserver_extra_arguments
    $controllermanager_merged_extra_arguments = $controllermanager_extra_arguments

    $apiserver_merged_extra_volumes = $apiserver_extra_volumes
    $controllermanager_merged_extra_volumes = $controllermanager_extra_volumes
  }

  # to_yaml emits a complete YAML document, so we must remove the leading '---'
  $kubeadm_extra_config_yaml = regsubst(to_yaml($kubeadm_extra_config), '^---\n', '')
  $kubelet_extra_config_yaml = regsubst(to_yaml($kubelet_extra_config), '^---\n', '')
  $kubelet_extra_config_alpha1_yaml = regsubst(to_yaml($kubelet_extra_config_alpha1), '^---\n', '')

  $config_version = $kubernetes_version ? {
    /1.1(0|1)/   => 'v1alpha1',
    /1.12/       => 'v1alpha3',
    /1.1(3|4|5)/ => 'v1beta1',
    default      => 'v1beta2',
  }

  file { $config_file:
    ensure  => present,
    content => template("kubernetes/${config_version}/config_kubeadm.yaml.erb"),
    mode    => '0600',
  }
}
