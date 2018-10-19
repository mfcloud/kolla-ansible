===========
Quick Start
===========

This guide provides step by step instructions to deploy OpenStack compute node
to join into an existing OpenStack controller using ansible on LinuxONE KVM
host.

LinuxONE KVM host requirements
==============================

If plan to deploy OpenStack compute node on one or more LinuxONE KVM hosts, choose
one of the LinuxONE KVM host as deploy node, which will be setup as ansible
control node; Other LinuxONE KVM hosts will be ansible managed nodes.

The ansible control node must satisfy the following minimum requirements:

- Base operating system installed
- 1 network interface
- 20GB disk space

The ansible managed nodes must satisfy the following minimum requirements:

- Base operating system installed
- 1 network interface configured, can be connected from ansible control node by
  ssh

.. note::

    - Currently, only support SLES12SP3 LinuxONE KVM host. Will add more distros
      support in future.
    - Root access to all LinuxONE KVM hosts are required.
    - Requirements of cpu and memory are depends on the workload you plan to run
      on each LinuxONE KVM hosts.

Install dependencies
====================

SLES12SP3
---------

For all the LinuxONE ansible managed nodes, no additional install dependencies
required.

For LinuxONE ansible control node, dependencies are:

- ansible
- sshpass

Prepare install media
^^^^^^^^^^^^^^^^^^^^^

Download below install media, and upload on to LinuxONE ansible control node:

- SLE-12-SP3-Server-DVD-s390x-GM-DVD1.iso
- SLE-12-SP3-SDK-DVD-s390x-GM-DVD1.iso
- OpenStack repository for SLES12SP3

  * e.g. you can download from opensuse download server. Sample download command:

    ``wget -r -p -np -k http://download.opensuse.org/repositories/Cloud:/OpenStack:/Ocata/SLE_12_SP3/``

- sshpass rpm package

  * Sample download command:

    ``wget https://download.opensuse.org/repositories/network/SLE_12_SP3/s390x/sshpass-1.06-7.2.s390x.rpm``

- Download deploy scripts from: `<https://github.com/mfcloud/kolla-ansible>`_ 

Install dependencies on LinuxONE ansible control node
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**Install ansible** Ansible and its dependency packages are from
``SLE-12-SP3-Server-DVD-s390x-GM-DVD1`` and ``OpenStack repository for SLES12SP3``,
so add the reposotoriese into zypper on LinuxONE ansible control node:
::

    mount -o loop -t iso9660 SLE-12-SP3-Server-DVD-s390x-GM-DVD1.iso <path-to-mount>
    zypper ar -G file://<path-to-mount> sles12-sp3-dvd1
    zypper ar -G file://<path-to-openstack-repository> openstack-ocata
    zypper install -y ansible

To enable specify ssh password in ansible inventory file, edit the ansible config
file ``/etc/ansible/ansible.cfg``:
::

    host_key_checking = False

**Install sshpass** Install sshpass command:
::

    zypper install -y sshpass-1.06-7.2.s390x.rpm

Prepare ansible inventory file
==============================

The sample inventory file is located at ``kolla-ansible/compute-only/inv-host-file``:

- Add LinuxONE ansible control node into ``deploy_node`` section, with
  ``ansible_ssh_pass`` specified
- Add LinuxONE ansible managed nodes into ``compute_nodes`` section, with
  ``ansible_ssh_pass`` specified
- Add OpenStack controller node into ``controller`` section, with
  ``ansible_ssh_pass`` specified

Deploy LinuxONE OpenStack compute node
======================================

Issue below command to trigger the deployment:
::

    cd <path-to-kolla-ansib>e/compute-only
    ansible-playbook -i <ansible-inventory-file> main.yml
