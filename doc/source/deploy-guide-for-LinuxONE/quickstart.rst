.. quickstart:

===========
Quick Start
===========

This guide provides step by step instructions to use Kolla-ansible to deploy
OpenStack controller services on x86 server and OpenStack compute of KVM on
LinuxONE.


System requirements
~~~~~~~~~~~~~~~~~~~~~~

The following three classes of nodes are defined in the architecture: deployer,
controller, and compute.

- ``deployer node``: This is used for running local docker registry, package repo, and
  also where the kolla-ansible tool would be installed, configured and run.

  System requirements:
   * Ubuntu 16.04/x86_64 platform
   * 1 network interfaces
   * 8GB main memory
   * 400GB disk space
- ``controller node``: This is where the OpenStack controller services will be deployed onto.

  System requirements:
   * Ubuntu 16.04/x86_64 platform
   * 2 network interfaces
   * 8GB main memory
   * 40GB disk space
- ``compute node``: This is where the OpenStack compute services will be deployed onto.

  System requirements:
   * Ubuntu 16.04/LinuxONE platform
   * 1 network interface
   * 8GB main memory
   * 10GB disk space

.. note::

    - Root access to all the nodes is required.
    - The deployer node can be the same node with controller node.


Setup Deployer Node
~~~~~~~~~~~~~~~~~~~~

Prepare files used to setup the deployer node
---------------------------------------------

The deployer node is supposed to run the local package repository server which is used
by the kolla-ansible deploy process to install packages on target nodes including controller
and compute nodes, run the local pypi server which serves python packages, run the local docker
image repository to replace the need to pull images from Docker Hub. With these local servers,
this omits the needs of network connection of the deploy process.

These functions require several files to be prepared and put onto the deployer node. The files
should be organized as following:

::

    root@deployer:/data/OpenStackCE# tree -L 1
    .
    |-- deployment-docker-images.tar
    |-- docker-ce
    |-- docker-registry
    |-- kolla-ansible
    |-- pypi
    `-- ubuntu-mirror

-  ``deployment-docker-images.tar`` - Contains the three docker images: pypiserver, nginx, and registry
   which will be used to run the local pypi server, package repository and docker image registry
   respectively.
-  ``docker-ce`` - Contains docker-ce deb package and its dependency used to install docker-ce on the
   deployer node.
-  ``docker-registry`` - Contains the built docker images used to deploy OpenStack services, including
   both the x86_64 arch images for controller node and s390x arch images for compute node.
-  ``pypi`` - Contains the needed python packages used by kolla-ansible to deploy OpenStack services.
-  ``ubuntu-mirrir`` - Contains the ubuntu mirror and docker mirror which provides all the deb packages
   used by kolla-ansible in the deploy process.

These files need to be put into a single folder, generally we recommend you to put them into /data/OpenStackCE
which is the default folder used by the setup tool to find the required files. Specify the folder base when
running the setup tool if you use other folder name.

The following guides will use the /data/OpenStackCE as the folder name for the required files.


Run setup tool
--------------

The /data/OpenStackCE/kolla-ansible holds the tool used to setup the deployer.
You can check the tool usage by running:
::

    /data/OpenStackCE/kolla-ansible/tools/setup-deployment-server -h

Then run the tool with your arguments if required:
::

    /data/OpenStackCE/kolla-ansible/tools/setup-deployment-server

This tool would automatically do the following jobs:

- install and run docker daemon
- run local docker registry
- run local package repository server
- run local pypi server
- configure deployer node to use local repository
- install kolla-ansible and its dependencies
- collect and generate configuration templates into ``etc/kolla``

The tool would print actions taken by each step and the corresponding result. Please make sure each step finishes
successfully.

When the tool finishes successfully, you can see there are three containers running as following:
::

    root@deployer:/data/OpenStackCE# docker ps
    CONTAINER ID        IMAGE               COMMAND                  CREATED             STATUS              PORTS                    NAMES
    51417101e46f        pypiserver:master   "pypi-server -p 8080…"   About an hour ago   Up About an hour    0.0.0.0:8080->8080/tcp   pypiserver
    85de3de2fedb        registry:2          "/entrypoint.sh /etc…"   About an hour ago   Up About an hour    0.0.0.0:5000->5000/tcp   registry
    430bee95f31b        nginx:1.15.3        "nginx -g 'daemon of…"   About an hour ago   Up About an hour    0.0.0.0:8000->80/tcp     nginx

Also, you can see the deployer node has been setup to use local PYPI server and package repository:
::

    root@deployer:/data/OpenStackCE# cat /etc/apt/sources.list
    deb [arch=amd64] http://DEPLOYER_IP:8000/archive.ubuntu.com/ubuntu/ xenial main restricted universe multiverse
    deb [arch=amd64] http://DEPLOYER_IP:8000/archive.ubuntu.com/ubuntu/ xenial-updates main restricted universe multiverse
    deb [arch=amd64] http://DEPLOYER_IP:8000/archive.ubuntu.com/ubuntu/ xenial-backports main restricted universe multiverse
    deb [arch=amd64] http://DEPLOYER_IP:8000/security.ubuntu.com/ubuntu xenial-security main restricted


Prepare initial configuration
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The configuration steps includes inventory file, global settings, passwords used by OpenStack services, and OpenStack
service configurations. And these steps all need to be done on the deployer node.

Inventory
---------

Inventory is an ansible file for user to specify target nodes, roles and access credentials.

The deployer setup tool would automatically generate the configuration example files for you under the ``/etc/kolla``
folder:
::

    root@deployer:~# ls /etc/kolla
    all-in-one  config  globals.yml  multinode  openstack-ce-presetups.sh  passwords.yml

Since we have separate host for controller node and compute nodes, so we need to edit the ``multinode`` inventory file.
Edit the first section of ``multinode`` with connection details of your environment, for example:

::

    # For other connection method, please refer to the ansible document.
    [control]
    testcont network_interface=eth0 ansible_connection=ssh ansible_user=root ansible_ssh_pass=PASSWD

    # when you specify group_name:children, it will use contents of group specified.
    [network:children]
    control

    # inner-compute is the groups of compute nodes which do not have
    # external reachability
    [inner-compute]
    
    # external-compute is the groups of compute nodes which can reach
    # outside
    [external-compute]
    testcomp network_interface=enc123 ansible_connection=ssh ansible_user=root ansible_ssh_pass=PASSWD
    
    [compute:children]
    inner-compute
    external-compute
    
    [monitoring]
    
    [storage]
    
    [deployment]
    localhost       ansible_connection=local

Please customize the example contents to suit your own environment:

- The ``network_interface`` value under the ``control`` and ``external-compute`` section should be the name of interface
  which is used for the deployer to communicate with the controller or compute node respectively.
- More than one compute node can be specified in the inventory file.
- The ``testcont`` and ``testcomp`` should be the hostname of the target controller node and compute node respectively.
  And the hostname must be resolvable on the deployer node, otherwise please specify the IP address and hostname pair
  in the /etc/hosts on the deployer node.

To learn more about inventory files, check
`Ansible documentation <http://docs.ansible.com/ansible/latest/intro_inventory.html>`_.

OpenStack Service Passwords
---------------------------

The ``/etc/kolla/passwords.yml`` file contains all the passwords that can be specified and will be used by the kolla-ansible
deploy process. Initially all passwords are blank in this file and can be filled either manually or by running random password
generator:

::

    kolla-genpwd

This tool would fill the ``/etc/kolla/passwords.yml`` file with randomly generated passwords. You can further update specific
passwords as you need.


Kolla-ansible Global Settings
-----------------------------

``/etc/kolla/globals.yml`` is the main configuration file used by Kolla-ansible. The deployer setup tool has automatically setup 
most of the required options for you, including:
::

    ---
    kolla_base_distro: "ubuntu"
    kolla_install_type: "binary"
    openstack_release: "queens"
    node_custom_config: "/etc/kolla/config"
    docker_registry: "DEPLOYER_IP:5000"
    docker_namespace: "linuxone"
    local_docker_apt_url: "http://DEPLOYER_IP:8000/download.docker.com/linux/ubuntu"
    enable_fluentd: "no"
    enable_haproxy: "no"
    enable_heat: "no"

There are other options that are required to be specified as fit to your environment:

::

    # Set the kolla_internal_vip_address value to the IP address of your "network_interface" as set in the [control] section of
    # the inventory file.
    kolla_internal_vip_address: "YOURIP"
    # Set the neutron_external_interface to the interface given to neutron as its external network port. This interface should be
    # active without IP address.
    neutron_external_interface: "INTERFACE"
    # Optional but suggest to enable the following option for further debug convenience.
    openstack_logging_debug: "True"


OpenStack Service Configurations
--------------------------------

For deploy to kvm compute node on LinuxONE, some configurations are required for nova-compute service.

The deployer node setup tool automatically generated the /etc/kolla/config/nova/nova-compute.conf file that contains the required options,
you can customize this file to adjust your environment settings.

Other Configurations:

Kolla-ansible allows the operator to override configuration of services. Kolla-ansible will
look for a file in ``/etc/kolla/config/<< service name >>/<< config file >>``.
This can be done per-project, per-service or per-service-on-specified-host.


Deployment
~~~~~~~~~~

After configuration is set, we can proceed to the deployment phase.

* Bootstrap servers to setup basic host-level dependencies:

  ::

      kolla-ansible -i /etc/kolla/multinode bootstrap-servers

* Do pre-deployment checks for hosts:

  ::

      kolla-ansible -i /etc/kolla/multinode prechecks


* Proceed to actual OpenStack deployment:

  ::

      kolla-ansible -i /etc/kolla/multinode deploy

When this playbook finishes successfully, OpenStack should be up, running and functional!


Using OpenStack
~~~~~~~~~~~~~~~

OpenStack requires an openrc file where credentials for admin user etc are set.
To generate this file run

::

    kolla-ansible post-deploy
    . /etc/kolla/admin-openrc.sh

Install basic OpenStack CLI clients:

::

    pip install python-openstackclient python-glanceclient python-neutronclient

