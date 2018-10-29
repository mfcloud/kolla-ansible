
.. _`prepare files required by the deployment server`:

=====================================================
Prepare files required to setup the deployment server
=====================================================

This guide provides step by step instructions to prepare files that are required
to setup the deployment server, so that the kolla-ansible project can be used to
deploy OpenStack controller services on x86 server and OpenStack compute of KVM on
LinuxONE, without Internet connection requirements.


System requirements
~~~~~~~~~~~~~~~~~~~

Two servers are needed to do the preparation steps:

- One x86_64 server which usually can be the same server as the deployment server.

 System requirements:
   * Ubuntu 16.04/x86_64 platform
   * 1 network interfaces
   * 8GB main memory
   * 400GB disk space

- One server on LinuxONE which can be same server as the target compute node.

  System requirements:
   * Ubuntu 16.04/LinuxONE platform
   * 1 network interface
   * 8GB main memory
   * 10GB disk space

Build docker images
~~~~~~~~~~~~~~~~~~~

Pre-requirements
----------------

We need to build images for both the x86_64 and LinuxONE platform, so the build action
need to be done on both the x86_64 and LinuxONE server. Before the build, there are several
preparations need to be done on the two servers.

We will use ``$KOLLA_BASE`` to represent the kolla project base folder and the ``$x86_64_SERVER_IP``
to represent the IP address of the x86_64 server in this guide, please remember to replace the value
to suit your environment.


- pip and python should be installed on both of the two servers

- Clone kolla project from mfcloud/kolla on both of the two servers, and then install kolla.

  ::

      # git clone -b stable/queens https://github.com/mfcloud/kolla.git
      # cd $KOLLA_BASE
      # pip install .


  .. note::

      When install kolla on LinuxONE server, you may get following fatal errors:

      "c/_cffi_backend.c:15:17: fatal error: ffi.h: No such file or directory
      compilation terminated.
      error: command 's390x-linux-gnu-gcc' failed with exit status 1"

      If you got such error, please install the following packages to get out of this:

        ``apt-get install libffi-dev libssl-dev``

      And then re-install the kolla project.

- Install Docker on both of the two servers by refering to the
  `docker official documentation <https://docs.docker.com/>`__


  Make sure docker service is active and running:

  ::

    # systemctl status docker
    * docker.service - Docker Application Container Engine
       Loaded: loaded (/lib/systemd/system/docker.service; enabled; vendor preset: enabled)
      Drop-In: /etc/systemd/system/docker.service.d
               `-kolla.conf
       Active: active (running) since Wed 2018-10-24 03:41:47 EDT; 4 days ago
         Docs: https://docs.docker.com

- Run local docker image registry in container on the x86_64 server

  ::

    # mkdir -p /data/OpenStackCE/docker-registry
    # docker run -d --name registry --restart=always -p 5000:5000 -v /data/OpenStackCE/docker-registry:/var/lib/registry registry:2
    7039bf35141e3cad9c55a49b74d53c4aec250067ccbf606cad4f79cb93dc16cd
    # docker ps
    CONTAINER ID        IMAGE               COMMAND                  CREATED             STATUS              PORTS                    NAMES
    7039bf35141e        registry:2          "/entrypoint.sh /etc…"   14 seconds ago      Up 12 seconds       0.0.0.0:5000->5000/tcp   registry

- Update docker configuration on the two servers so that the insecure private image repository can be accessed.

  Create a file named /etc/docker/daemon.json with following content and then restart docker

  ::

        # cat /etc/docker/daemon.json
        {
          "insecure-registries": ["x86_64_SERVER_IP:5000"]
        }
        # systemctl restart docker


Build images for x86_64
-----------------------

On x86_64 server, build your images with the following commands:

  ::

    # mkdir -p /etc/kolla
    # cp $KOLLA_BASE/etc/kolla/kolla-build.conf.x86 /etc/kolla/kolla-build.conf
    # kolla-build --push --registry $x86_64_SERVER_IP:5000

Use the tool provided in the kolla project to rename the built images with suffix '-x86' added.

  ::

    # bash $KOLLA_BASE/multi-arch-repository/rename_image -a x86 -n linuxone -t queens -r $x86_64_SERVER_IP:5000 -p


Build images for LinuxONE
-------------------------

On LinuxONE server, build your images with the following commands, please replace the ``$KOLLA_BASE`` with your kolla project
base cloned in the pre-requirements section.

  ::

    # mkdir -p /etc/kolla
    # cp $KOLLA_BASE/etc/kolla/kolla-build.conf.s390x /etc/kolla/kolla-build.conf
    # kolla-build

Use the tool provided in the kolla project to rename the built images with suffix '-s390x' added, and then push
the re-tagged images to the image registry server running on the remote x86_64 server.

  ::

    # bash $KOLLA_BASE/multi-arch-repository/rename_image -a s390x -n linuxone -t queens -r $x86_64_SERVER_IP:5000


Create multi-arch image repository with docker manifest
-------------------------------------------------------

Since we have built docker images for two architecture: x86_64 and s390x, to make the docker client pull images with same
name and different architecture, we need to create manifests list to let the docker registry support multi-arch Docker image.
This step needs to be done on your x86 server where docker registry is served.

The manifest sub-command is required to build manifest list. So first we need to check whether this sub-command is available
on your docker client. If you got the following error:

  ::

    # docker manifest create --help
    docker manifest create is only supported on a Docker cli with experimental cli features enabled

then you need to enable the feature by creating a file called $HOME/.docker/config.json with the following contents:

  ::

    # cat ~/.docker/config.json
    {
      "experimental": "enabled"
    }

Then you can start to use the following tool on the x86_64 server to automatically create the image manifests and push to the
local docker image registry:

  ::

    # bash $KOLLA_BASE/multi-arch-repository/multi-arch -n linuxone -t queens -r localhost:5000


Download Ubuntu mirror
~~~~~~~~~~~~~~~~~~~~~~

To avoid the requirement of Internet access in the deploy process, we need to download the Ubuntu packages and put onto the deployment
server. This section contains step-by-step guides on how to use apt-mirror to download the mirror to local, all the steps need to be done
on the x86-64 server.

- Install apt-mirror

  ::

  # apt-get install -y apt-mirror

- Update the /etc/apt/mirror.list. Set the ``base_path`` value to a folder that has enough space to hold the mirror and add the following
  repository lines:

  ::

    deb-amd64 http://archive.ubuntu.com/ubuntu xenial main restricted universe multiverse
    deb-amd64 http://archive.ubuntu.com/ubuntu xenial-updates main restricted universe multiverse
    deb-amd64 http://archive.ubuntu.com/ubuntu xenial-backports main restricted universe multiverse
    deb-amd64 http://security.ubuntu.com/ubuntu xenial-security main restricted universe multiverse
    deb-amd64 https://download.docker.com/linux/ubuntu xenial stable
    deb-s390x http://us.ports.ubuntu.com/ubuntu-ports/ xenial main restricted universe multiverse
    deb-s390x http://us.ports.ubuntu.com/ubuntu-ports/ xenial-updates main restricted universe multiverse
    deb-s390x http://us.ports.ubuntu.com/ubuntu-ports/ xenial-backports main restricted universe multiverse
    deb-s390x http://ports.ubuntu.com/ubuntu-ports xenial-security main restricted universe multiverse
    deb-s390x https://download.docker.com/linux/ubuntu xenial stable
    clean http://archive.ubuntu.com/ubuntu
    clean http://security.ubuntu.com/ubuntu
    clean http://us.ports.ubuntu.com/ubuntu-ports/
    clean http://ports.ubuntu.com/ubuntu-ports
    clean https://download.docker.com/linux/ubuntu

- Run apt-mirror to start the download:

  ::

  # apt-mirror

- The download would take several hours depending on the mirror size. After the download succeeds, you can find the following folders
  under the ``base_path`` value: ``mirror``, ``skel``, ``var``. The ``mirror`` folder contains all the downloaded mirrors, use the following command
  to move the mirror to our target folder:

  ::

  # mv $base_path/mirror /data/OpenStackCE/ubuntu-mirror

- Download the gpg key of Docker repository.

  ::

    # wget -O /data/OpenStackCE/ubuntu-mirror/download.docker.com/linux/ubuntu/gpg https://download.docker.com/linux/ubuntu/gpg


Download required PYPI packages
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

When we use kolla-ansible to deploy OpenStack cloud, there are several python packages required which are usually downladed from the PYPI website.
To avoid the Internet requirement in the deploy process, we need to download the required packages to local and serve them from the deployment server.

The following steps required to be done on both the x86-64 server and the LinuxONE server.

- Clone kolla-ansible project.

  ::

  # git clone -b stable/queens https://github.com/mfcloud/kolla-ansible.git

- Update pip to use version 9.0.3

  Due to limitation of the pip2pi tool, we need to use pip of version 9.0.3 to work around some error.
  You can upgrade the pip to latest version after finish all the steps in this section.

  ::

  # pip install pip==9.0.3

- Install pip2pi

  ::

  # pip install pip2pi

- Prepare the list file of required python packages and their version.
  The list file is contained in the kolla-ansible project:

  ::

  # cp $KOLLA-ANSIBLE-BASE/tools/deployer_for_linuxone/pypi_list.$ARCH $HOME/pypi_list

  Please remember to customize the command to replace the ``$KOLLA-ANSIBLE-BASE`` to the cloned kolla-ansible project base and the ``$ARCH`` to either
  "x86" or "s390x" depending on the server architecture.

- Download the packages listed in the list file with the following scripts:


  ::

    # mkdir -p $HOME/pypi

  ::

    # cat $HOME/mypip2tgz.sh
    #!/bin/bash
    while read LINE
    do
    pip2tgz $HOME/pypi $LINE
    done < $HOME/pypi_list

  After this step finishes, all the required packages listed in the pypi_list file would be downloaded to the $HOME/pypi folder.

Please repeat the steps on both the x86-64 server and LinuxONE server. Then copy the packages downloaded for the two architecture onto one folder on the
x86-64 server, recommend to use ``/data/OpenStackCE/pypi`` which is the target folder to serve all the python packages required.


Collect and Save required docker images
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

To avoid Internet connection requirement, we need to serve the pypi packages, ubuntu mirror and the docker image registry on the deployment server.
We will run these servers in docker container, thus there are three docker images that need to be collected and put on the deployment server.

This section needs to be done on the x86-64 server.

- nginx docker image used to serve the ubuntu package repository

  ::

  # docker pull nginx:1.15.3

- registry docker image used to serve all the built docker images for deploying OpenStack Cloud

  ::

  # docker pull registry:2

- build pypiserver docker image used to serve the pip repository server

  ::

  # git clone https://github.com/pypiserver/pypiserver.git
  # cd pypiserver
  # docker build -t pypiserver:master .

- Save all the three docker images into an archive file

  ::

  # docker save -o /data/OpenStackCE/deployment-docker-images.tar nginx:1.15.3 registry:2 pypiserver:master


Collect docker-ce and its dependency package
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Docker installation is required as the first step to setup the deployment server, it is required to run the previously mentioned repository servers.
So we need to collect the docker-ce and its dependency packages in order to install them onto the deployment server without Internet connection
requirements.

This section needs to be done on the x86-64 server.

  ::

  # mkdir -p /data/OpenStackCE/docker-ce
  # cp /data/OpenStackCE/ubuntu-mirror/download.docker.com/linux/ubuntu/dists/xenial/pool/stable/amd64/docker-ce_18.06.1~ce~3-0~ubuntu_amd64.deb /data/OpenStackCE/docker-ce/
  # cp /data/OpenStackCE/ubuntu-mirror/archive.ubuntu.com/ubuntu/pool/main/libt/libtool/libltdl7_2.4.6-0.1_amd64.deb /data/OpenStackCE/docker-ce/

Clone kolla-ansible project from github
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The ``mfcloud/kolla-ansible`` on github contains the corresponding code used to deploy OpenStack Cloud with all the prepared files here. Here we will
clone the project to local.

  ::

  # git clone -b stable/queens https://github.com/mfcloud/kolla-ansible.git /data/OpenStackCE/kolla-ansible

With all the above steps in this guide done, the ``/data/OpenStackCE`` folder contains all the files required to setup the deployment server.

