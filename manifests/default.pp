$home = '/home/vagrant'
Exec {
   path => ['/usr/sbin', '/usr/bin', '/sbin', '/bin']
}

# --- Preinstallation stage ---
stage { 'preinstall':
   before => Stage['main']
}

class apt_get_update {
   exec { 'apt-get -y update':
      timeout => 0,
      unless => "test -e ${home}/.rvm"
   }
   exec { 'install_necessary_packages':
      command => "sudo apt-get -y install build-essential libssl-dev libyaml-dev git libtool libxslt-dev libxml2-dev libpq-dev gawk curl pngcrush imagemagick python-software-properties && sudo mkdir -p .preinstall && sudo touch .preinstall/install_necessary_packages",
      timeout => 0,
      unless => "test -e .preinstall/install_necessary_packages"
   }
}
class { 'apt_get_update':
   stage => preinstall
}

# --- PostgreSQL ---
class install_postgres {
   exec { 'install_postgresql':
      command => "sudo apt-get -y install postgresql postgresql-client libpq-dev && sudo touch .preinstall/postgresql-client",
      timeout => 0,
      unless => "test -e .preinstall/postgresql-client",
      require => Exec['install_necessary_packages'],
   }
   service { 'postgresql':
      ensure => running,
   }
}
include install_postgres

# --- Redis ---
class install_redis {
   exec { 'install_redis_db':
      command => "sudo apt-add-repository -y ppa:rwky/redis && sudo apt-get update && sudo apt-get install redis-server && sudo touch .preinstall/redis",
      timeout => 0,
      unless => "test -e .preinstall/redis",
      require => Exec['install_postgresql'],
   }
}
include install_redis

# --- Nginx ---
class install_nginx {
   exec { 'install_nginx_proxy':
      command => "sudo apt-get remove '^nginx.*$' && sudo echo 'deb http://nginx.org/packages/ubuntu/ precise nginx' > /etc/apt/sources.list.d/nginx.list && sudo echo 'deb-src http://nginx.org/packages/ubuntu/ precise nginx' >> /etc/apt/sources.list.d/nginx.list && curl http://nginx.org/keys/nginx_signing.key | sudo apt-key add - && sudo apt-get update && sudo apt-get -y install nginx && sudo touch .preinstall/nginx",
      timeout => 0,
      unless => "test -e .preinstall/nginx",
      require => Exec['install_redis_db'],
   }
}
include install_nginx

# --- Ruby with RVM ---
class install_rubyrvm {
   exec { 'adduser_discourse':
      command => "sudo adduser --shell /bin/bash --gecos 'Discourse application' discourse",
      timeout => 0,
      unless => "test -e /home/discourse",
      require => Exec['install_nginx_proxy'],
   }
   exec { 'copy_discourse':
      command => "sudo install -d -m 755 -o discourse -g discourse /var/www/discourse",
      timeout => 0,
      unless => "test -e /var/www/discourse",
      require => Exec['adduser_discourse'],
   }
   exec { 'adduser_discourse_postgresql':
      command => "sudo -u postgres createuser -s discourse && sudo touch .preinstall/discourse_postgresql",
      timeout => 0,
      unless => "test -e .preinstall/discourse_postgresql",
      require => Exec['copy_discourse'],
   }
   exec { 'install_rvm_prereq':
      command => "sudo apt-get -y install pkg-config libreadline6-dev libsqlite3-dev sqlite3 autoconf libgdbm-dev libncurses5-dev bison libffi-dev && sudo mkdir -p .rvm-prereq && sudo touch .rvm-prereq/rvm",
      timeout => 0,
      unless => "test -e .rvm-prereq/rvm",
      require => Exec['adduser_discourse_postgresql'],
   }
   exec { 'get_rvm_keys':
      command => "sudo su - discourse -c 'command curl -sSL https://rvm.io/mpapis.asc | gpg --import -'",
      timeout => 0,
      unless => "test -e /home/discourse/.gnupg/trustdb.gpg",
      require => Exec['install_rvm_prereq'],
   }
   exec { 'install_rvm':
      command => "sudo su - discourse -c 'curl -s -S -L https://get.rvm.io | bash -s stable'",
      timeout => 0,
      unless => "test -e /home/discourse/.rvm/scripts/rvm",
      require => Exec['get_rvm_keys'],
   }
   exec { 'run_rvm':
      command => "sudo su - discourse -c '. ~/.rvm/scripts/rvm && mkdir -p ~/.rvm/rmv-run'",
      timeout => 0,
      unless => "test -e /home/discourse/.rvm/rvm-run",
      require => Exec['install_rvm'],
   }
   exec { 'install_ruby_now':
      command => "sudo su - discourse -c 'rvm install 2.0.0 && rvm use 2.0.0 --default && gem install bundler && mkdir -p ~/.ruby-now && touch ~/.ruby-now/ruby'",
      timeout => 0,
      unless => "test -e /home/discourse/.ruby-now/ruby",
      require => Exec['run_rvm'],
   }
}
include install_rubyrvm

# --- Discourse Main ---
class install_discourse_main {
   exec { 'clone_discourse':
      command => "sudo su - discourse -c 'git clone git://github.com/discourse/discourse.git /var/www/discourse'",
      timeout => 0,
      unless => "test -e /var/www/discourse/.git",
      require => Exec['install_ruby_now'],
   }
   exec { 'discourse_installation':
      command => "sudo su - discourse -c 'cd /var/www/discourse && git checkout latest-release && bundle install --deployment --without test && mkdir -p ~/.discourse-main && touch ~/.discourse-main/install'",
      timeout => 0,
      unless => "test -e /home/discourse/.discourse-main/install",
      require => Exec['clone_discourse'],
   }
}
include install_discourse_main


# --- Configure Discourse ---
class configure_discourse {
   exec { 'configure_discourse_now':
      command => "sudo su - discourse -c 'cd /var/www/discourse/config && cp discourse_quickstart.conf discourse.conf && cp discourse.pill.sample discourse.pill'",
      unless => "test -e /var/www/discourse/config/discourse.conf && test -e /var/www/discourse/config/discourse.pill",
      require => Exec['discourse_installation'],
   }
   exec { 'configure_discourse_hostname':
      command => "sudo su - discourse -c \"cd /var/www/discourse/config && sed -i s/"hostname = \"discourse.example.com\""/"hostname = \"localhost\""/g discourse.conf\"",
      require => Exec['configure_discourse_now'],
   }
}
include configure_discourse
