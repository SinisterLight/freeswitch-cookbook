## Cookbook Name:: freeswitch
## Recipe:: default
##
## Copyright 2012, "Twelve Tone Software" <lee@twelvetone.info>
##
##    This program is free software: you can redistribute it and/or modify
##    it under the terms of the GNU General Public License as published by
##    the Free Software Foundation, either version 3 of the License, or
##    (at your option) any later version.
##
##    This program is distributed in the hope that it will be useful,
##    but WITHOUT ANY WARRANTY; without even the implied warranty of
##    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
##    GNU General Public License for more details.
##
##    You should have received a copy of the GNU General Public License
##    along with this program.  If not, see <http://www.gnu.org/licenses/>.
##
#
## Freeswitch cookbook
## ZRTP media pass-through proxy mode

## Build requirements
package "autoconf"
package "automake"
package "g++"
package "git-core"
package "libjpeg62-dev"
package "libncurses5-dev"
package "libtool"
package "make"
package "python-dev"
package "gawk"
package "pkg-config"
package "gnutls-bin"
package "libsqlite3-dev"
package "bison"
## install packages for mod_shout for mp3 playback

# user generation dependencies
gem_package "xml-simple"
package "pwgen"

# get source
execute "git_clone" do
  command "git clone -b #{node[:freeswitch][:git_branch]} #{node[:freeswitch][:git_uri]} freeswitch"
  cwd "/usr/local/src"
  creates "/usr/local/src/freeswitch"
end

template "/usr/local/src/freeswitch/modules.conf" do
  source "modules.conf.erb"
end

# compile source and install
script "compile_freeswitch" do
  interpreter "/bin/bash"
  cwd "/usr/local/src/freeswitch"
  code <<-EOF
  ./bootstrap.sh
  ./configure
  make clean
  make
  make config-rayo
  make install
EOF
  not_if "test -f #{node[:freeswitch][:path]}/freeswitch"
end

# install init script
template "/etc/init.d/freeswitch" do
  source "freeswitch.init.erb"
  mode 0755
end

# install defaults
template "/etc/default/freeswitch" do
  source "freeswitch.default.erb"
  mode 0644
end

group node[:freeswitch][:group] do
  action :create
end

# create non-root user
user node[:freeswitch][:user] do
  system true
  shell "/bin/bash"
  home node[:freeswitch][:homedir]
  gid node[:freeswitch][:group]
end

# change ownership of homedir
execute "fs_homedir_ownership" do
  cwd node[:freeswitch][:homedir]
  command "chown -R #{node[:freeswitch][:user]}:#{node[:freeswitch][:group]} ."
end

# define service
service node[:freeswitch][:service] do
  supports :restart => true, :start => true
  action [:enable]
end

# SSL actions
cookbook_file "#{node[:freeswitch][:homedir]}/bin/gentls_cert" do
  source "gentls_cert"
  owner node[:freeswitch][:user]
  group node[:freeswitch][:group]
  mode 0755
end

execute "build_ca" do
  user "freeswitch"
  cwd "#{node[:freeswitch][:path]}"
  command "./gentls_cert setup -cn #{node[:freeswitch][:domain]} -alt DNS:#{node[:freeswitch][:domain]} -org #{node[:freeswitch][:domain]}"
  creates "#{node[:freeswitch][:homedir]}/conf/ssl/CA/cakey.pem"
end

execute "gen_server_cert" do
  user "freeswitch"
  cwd "#{node[:freeswitch][:path]}"
  command "./gentls_cert create_server -quiet -cn #{node[:freeswitch][:domain]} -alt DNS:#{node[:freeswitch][:domain]} -org #{node[:freeswitch][:domain]}"
  creates "#{node[:freeswitch][:homedir]}/conf/ssl/agent.pem"
end

# set global variables
template "#{node[:freeswitch][:homedir]}/conf/vars.xml" do
  owner node[:freeswitch][:user]
  group node[:freeswitch][:group]
  source "vars.xml.erb"
  mode 0644
end

template "#{node[:freeswitch][:homedir]}/scripts/gen_users" do
  source "gen_users.rb.erb"
  owner node[:freeswitch][:user]
  group node[:freeswitch][:group]
  mode 0755
end

template "#{node[:freeswitch][:homedir]}/conf/dialplan/default.xml" do
  source "default.xml.erb"
  owner node[:freeswitch][:user]
  group node[:freeswitch][:group]
  mode 0755
  variables :head_fragments => node[:freeswitch][:dialplan][:head_fragments],
            :tail_fragments => node[:freeswitch][:dialplan][:tail_fragments]
end

template "#{node[:freeswitch][:homedir]}/conf/autoload_configs/event_socket.conf.xml" do
  source "event_socket.conf.xml.erb"
  owner node[:freeswitch][:user]
  group node[:freeswitch][:group]
  mode 0755
end

template "#{node[:freeswitch][:homedir]}/conf/autoload_configs/acl.conf.xml" do
  source "acl.conf.xml.erb"
  owner node[:freeswitch][:user]
  group node[:freeswitch][:group]
  mode 0755
  variables :acl_domains => node[:freeswitch][:acl][:domains]
end

template "#{node[:freeswitch][:homedir]}/conf/dialplan/public.xml" do
  source "public.xml.erb"
  owner node[:freeswitch][:user]
  group node[:freeswitch][:group]
  mode 0755
  variables :public_head_fragments => node[:freeswitch][:dialplan][:public_head_fragments],
            :public_tail_fragments => node[:freeswitch][:dialplan][:public_tail_fragments]
end

node[:freeswitch][:extra_sip_profiles].each do |p|
  template "#{node[:freeswitch][:homedir]}/conf/sip_profiles/#{p[:folder]}/#{p[:file_name]}.xml" do
    source "sip_profile_tpl.xml.erb"
    owner node[:freeswitch][:user]
    group node[:freeswitch][:group]
    mode 0755
    variables :profile_name => p[:profile_name],
              :contents => p[:contents]
  end
end

template "#{node[:freeswitch][:homedir]}/conf/autoload_configs/modules.conf.xml" do
  source "modules.conf.xml.erb"
  owner node[:freeswitch][:user]
  group node[:freeswitch][:group]
  mode 0755
  notifies :restart, "service[#{node[:freeswitch][:service]}]"
end

template "#{node[:freeswitch][:homedir]}/conf/autoload_configs/rayo.conf.xml" do
  source "rayo.conf.xml.erb"
  owner node[:freeswitch][:user]
  group node[:freeswitch][:group]
  mode 0755
  variables :listeners => node[:freeswitch][:modules][:rayo][:listeners]
  notifies :restart, "service[#{node[:freeswitch][:service]}]"
end
