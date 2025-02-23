control 'container' do
  impact 0.5
  describe docker_container('mysql-server-%%MAJOR_VERSION%%') do
    it { should exist }
    it { should be_running }
    its('repo') { should eq 'mysql/mysql-server' }
    its('ports') { should eq '%%PORTS%%' }
    its('command') { should match '/entrypoint.sh mysqld' }
  end
end
control 'packages' do
  impact 0.5
  describe package('%%MYSQL_SERVER_PACKAGE_NAME%%') do
    it { should be_installed }
    its ('version') { should match '%%MYSQL_VERSION%%.*' }
  end
  describe package('%%MYSQL_SHELL_PACKAGE_NAME%%') do
    it { should be_installed }
    its ('version') { should match '%%MYSQL_VERSION%%.*' }
  end
end
