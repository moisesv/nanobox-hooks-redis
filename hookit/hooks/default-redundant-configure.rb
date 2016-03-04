include Hooky::Redis

# Setup
boxfile = converge( Hooky::Redis::BOXFILE_DEFAULTS, payload[:boxfile] )

# set redis config
ip        = `ifconfig eth0 | awk '/inet addr/ {print $2}' | cut -f2 -d':'`.to_s.strip
master_ip = payload[:generation][:members].select { |mem| mem[:role] == 'primary'}[0][:local_ip]
master    = (master_ip == ip) ? false : master_ip
sentinel  = (payload[:generation][:members].select { |mem| mem[:role] == 'monitor'}[0][:local_ip] == ip) ? master_ip : '127.0.0.1'
total_mem = `vmstat -s | grep 'total memory' | awk '{print $1}'`.to_i
cgroup_mem = `cat /sys/fs/cgroup/memory/memory.limit_in_bytes`.to_i
maxmemory = [ total_mem / 1024, cgroup_mem / 1024 / 1024 ].min

# Import service (and start)
directory '/etc/service/sentinel' do
  recursive true
end

directory '/etc/service/sentinel/log' do
  recursive true
end

directory '/etc/service/proxy' do
  recursive true
end

directory '/etc/service/proxy/log' do
  recursive true
end

# configure redis for redundancy
template '/data/etc/redis/redis.conf' do
  source 'redis-redundant.conf.erb'
  mode 0644
  variables ({ boxfile: boxfile , slaveof: master, maxmemory: maxmemory})
  owner 'gonano'
  group 'gonano'
end

# configure sentinel to provide redundancy
template '/data/etc/redis/sentinel.conf' do
  source 'sentinel.conf.erb'
  mode 0644
  variables ({ master: master_ip })
  owner 'gonano'
  group 'gonano'
end

# configure redis-proxy to provide high availability and interaction with sentinel
template '/data/etc/redis/redis-proxy.conf' do
  source 'redis-proxy.conf.erb'
  mode 0644
  variables ({ sentinel_ip: sentinel })
  owner 'gonano'
  group 'gonano'
end

# start sentinel
template '/etc/service/sentinel/log/run' do
  mode 0755
  source 'log-run.erb'
  variables ({ svc: "sentinel", dependency: "cache" })
end

template '/etc/service/sentinel/run' do
  mode 0755
  variables ({ exec: "redis-server /data/etc/redis/sentinel.conf --sentinel 2>&1" })
end

# start redis-proxy
template '/etc/service/proxy/log/run' do
  mode 0755
  source 'log-run.erb'
  variables ({ svc: "proxy", dependency: "sentinel" })
end

template '/etc/service/proxy/run' do
  mode 0755
  variables ({ exec: "/data/redundis/redis_proxy.lua /data/etc/redis/redis-proxy.conf 2>&1" })
end