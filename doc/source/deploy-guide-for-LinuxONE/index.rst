
=======================================================================
Deploy guide for using kolla-ansible to deploy compute node on LinuxONE
=======================================================================

Overview
========

This project provide deployment tools to deploy OpenStack controller services
on x86 controller and compute services for kvm on LinuxONE. The code core is
based on the openstack/kolla-ansible project which deploys OpenStack services
and infrastructure components in Docker containers permitting operators with
minimal experience to deploy OpenStack quickly.


Getting Started
===============

For information on building container images for use with Kolla-Ansible, please
refer to the `Kolla image documentation
<https://docs.openstack.org/kolla/latest/>`_.

Learn about Kolla-Ansible by reading the documentation online
`docs.openstack.org <https://docs.openstack.org/kolla-ansible/latest/>`__.


OpenStack services
------------------

The following OpenStack projects can be deployed by this project:

- `Glance <https://docs.openstack.org/glance/latest/>`__
- `Horizon <https://docs.openstack.org/horizon/latest/>`__
- `Keystone <https://docs.openstack.org/keystone/latest/>`__
- `Neutron <https://docs.openstack.org/neutron/latest/>`__
- `Nova <https://docs.openstack.org/nova/latest/>`__


Infrastructure components
-------------------------

The following infrastructure components are supported:

- `MariaDB <https://mariadb.com/kb/en/library/>`__ for highly available MySQL databases.
- `Memcached <https://memcached.org/>`__ a distributed memory object caching system.
- `Open vSwitch <http://openvswitch.org/>`__ and Linuxbridge backends for Neutron.
- `RabbitMQ <https://www.rabbitmq.com/>`__ as a messaging backend for
  communication between services.


QuickStart Guide
----------------

.. toctree::
   :maxdepth: 1

   quickstart