#!/bin/bash

function usage {
    cat <<EOF
Usage: $0 [options]

Options:
    --repo-source, -s <repository_source>      Specify the repository source, local or network, default is network
    --repo-port, -r <repository_port>          Specify the port to be used by the local package repository server, default is 8000
    --pypi-port, -p <pypi_port>                Specify the port to be used by the local pypi server, default is 8080
    --docker-registry-port, -d <registry_port> Specify the port to be used by the local docker registry server, default is 5001
    --base-dir, -b <CE_base_dir>               Specify the base directory, default is /data
    --bind-addr, -a <bind_ip_addr>             Specify the ip addr of the deployment server used to communicate with target nodes.
                                               If not specified, will try to automatically get the address using ifconfig and exclude
                                               the address 127.0.0.1 and 172.17.0.1(which is used by docker0).
                                               If two or more address are filtered, will abort.
    --help, -h                                 Show this usage information
EOF
}


function section {
    echo ""
    echo "#####################################################################"
    echo "$1"
    echo "#####################################################################"
    echo ""
}

function check_status {
    rc=$1
    action=""
    if [[ $# -eq 2 ]]; then
        action=$2
    fi
    if [[ $rc -ne 0 ]]; then
        echo "$action: Failed."
        echo "Aborting."
        exit 1
    else
        echo "$action: Successfully."
    fi
}

function find_containers_to_kill {
    existed_containers=$(docker ps --format "{{.Names}}" -a)
    if [ "${existed_containers}" == "" ]; then
        echo ""
        return
    fi
    target_containers=($REPO_SERVER $DOCKER_REGISTRY $PYPI_SERVER)
    containers_to_kill=""
    for c in ${target_containers[@]}; do
        if [ $(echo "${existed_containers[@]}" | grep -wq $c && echo $?) -eq 0 ]; then
            containers_to_kill=${containers_to_kill}" "$c
        fi
    done
    echo "$containers_to_kill"
}


function get_bind_addr {
    ip=$(/sbin/ifconfig -a|grep inet|grep -v 127.0.0.1|grep -v inet6|grep -v 172.17.0.1|awk '{print $2}'|tr -d "addr:")
    count=$(echo "$ip" | wc -l)
    if [[ $count -gt 2 ]]; then
        echo "$count ip addresses are detected, please specify which to use explicitly."
        echo "Aborting."
        exit 1
    fi
    echo "$ip"
}


function start_docker {
    section "Start and check docker status"
    systemctl daemon-reload
    systemctl start docker
    status=`systemctl status docker -q --no-pager | grep "Active: active (running)"`
    rc=$(if [[ -z "$status" ]]; then echo 1;else echo 0;fi)
    check_status $rc "Start docker service"
}


function load_images {
    section "Load docker images used to run local repo, pypiserver and docker registry"
    docker load -i "${CE_BASE}/OpenStackCE/deployment-docker-images.tar" 1>/dev/null
    check_status $? "Load docker image"
}


function kill_containers {
    section "Stop and Remove existed CE repo containers"
    echo "Finding containers to kill..."
    containers_to_kill=$(find_containers_to_kill)
    if [ "${containers_to_kill}" != "" ]; then
        echo "Containers to kill: ${containers_to_kill}"
        echo "Stopping containers..."
        (docker stop -t 5 ${containers_to_kill} 2>&1) > /dev/null
        echo "Removing containers..."
        (docker rm -f ${containers_to_kill} 2>&1) > /dev/null
    else
        echo "No existed CE related containers Found."
    fi
}


function start_registry {
    section "Start local docker registry"
    docker run -d --name $DOCKER_REGISTRY --restart=always -v ${CE_BASE}/OpenStackCE/docker-registry-rhel:/var/lib/registry -p ${DOCKER_REGISTRY_PORT}:5000 $DOCKER_REGISTRY_IMG 1>/dev/null
    check_status $?
}


function start_repository {
    section "Start local package repository server"
    docker run -d --name $REPO_SERVER --restart=always -v ${CE_BASE}/OpenStackCE/rhel-repo:/usr/share/nginx/html:ro -p ${REPOSITORY_PORT}:80 $REPO_SERVER_IMG 1>/dev/null
    check_status $?
}


function setup_local_repo {
    section "Install docker-ce on deployer server"
    cd ${CE_BASE}/OpenStackCE/rhel-repo/x86_64/docker-ce/repo/main/redhat/7
    yum install -y container-selinux-2.74-1.el7.noarch.rpm
    yum install -y containerd.io-1.2.0-3.el7.x86_64.rpm  docker-ce-18.09.0-3.el7.x86_64.rpm  docker-ce-cli-18.09.0-3.el7.x86_64.rpm

    start_docker

    load_images

    kill_containers

    start_registry

    start_repository

    section "Start local PYPI server"
    docker run -d --name $PYPI_SERVER --restart=always -v ${CE_BASE}/OpenStackCE/pypi:/data/packages -p ${PYPI_PORT}:8080 $PYPI_SERVER_IMG 1>/dev/null
    check_status $?

    section "Generate bootstrap files including yum repo and pip.conf"
    mkdir -p ${CE_BASE}/OpenStackCE/bootstrap_files_rhel
    cp -f ${CE_BASE}/OpenStackCE/kolla-ansible/tools/deployer_for_linuxone/templates/rhel/* ${CE_BASE}/OpenStackCE/bootstrap_files_rhel/
    check_status $? "Copy local_yum.repo templates"
    echo "Install net-tools to use ifconfig command"
    cd ${CE_BASE}/OpenStackCE/rhel-repo/x86_64/ftp3
    yum install -y net-tools-2.0-0.24.20131004git.el7.x86_64.rpm
    server_ip=$(get_bind_addr)
    echo "Get server bind address: $server_ip"
    sed -i "s/SERVER:REPO_PORT/${server_ip}:${REPOSITORY_PORT}/g" ${CE_BASE}/OpenStackCE/bootstrap_files_rhel/*repo*
    sed -i "s/SERVER/${server_ip}/g" ${CE_BASE}/OpenStackCE/bootstrap_files_rhel/pip.conf
    sed -i "s/PORT/${PYPI_PORT}/g" ${CE_BASE}/OpenStackCE/bootstrap_files_rhel/pip.conf

    section "Setup deployment server to use local package repository and PYPI server"
    suffix=`date +%Y%m%d`
    cp -f ${CE_BASE}/OpenStackCE/bootstrap_files_rhel/local-yum.repo.x86 /etc/yum.repos.d/local-yum.repo
    check_status $? "Setup /etc/yum.repos.d/local-yum.repo"
#    yum update 1>/dev/null
#    check_status $? "Check repo with yum update command"
    mkdir -p ${HOME}/.pip
    cp -f ${CE_BASE}/OpenStackCE/bootstrap_files_rhel/pip.conf ${HOME}/.pip/pip.conf
    check_status $? "Setup ${HOME}/.pip/pip.conf"
}

#####################################################################


SHORT_OPTS="hs:r:p:b:d:a:"
LONG_OPTS="help,repo-source:,repo-port:,pypi-port:,docker-registry-port:,base-dir:,bind-addr:"
ARGS=$(getopt -o "${SHORT_OPTS}" -l "${LONG_OPTS}" --name "$0" -- "$@") || { usage >&2; exit 2; }

eval set -- "$ARGS"

CE_BASE="/data"
server_ip=$(get_bind_addr)

# CE related docker images
REPO_SERVER_IMG="nginx:1.15.3"
DOCKER_REGISTRY_IMG="registry:2"
PYPI_SERVER_IMG="pypiserver:master"
# docker container names
REPO_SERVER="nginx"
DOCKER_REGISTRY="registry"
PYPI_SERVER="pypiserver"

REPOSITORY_SOURCE="network"
REPOSITORY_PORT=8000
PYPI_PORT=8080
DOCKER_REGISTRY_PORT=5001
CE_BASE="/data"
BIND_ADDR=""

while [ "$#" -gt 0 ]; do
    case "$1" in

    (--repo-source|-s)
            REPOSITORY_SOURCE="$2"
            shift 2
            ;;

    (--repo-port|-r)
            REPOSITORY_PORT="$2"
            shift 2
            ;;

    (--pypi-port|-p)
            PYPI_PORT="$2"
            shift 2
            ;;

    (--docker-registry-port|-d)
            DOCKER_REGISTRY_PORT="$2"
            shift 2
            ;;

    (--base-dir|-b)
            CE_BASE="$2"
            shift 2
            ;;

    (--bind-addr|-a)
            BIND_ADDR="$2"
            shift 2
            ;;

    (--help|-h)
            usage
            shift
            exit 0
            ;;

    (--)
            shift
            break
            ;;

    (*)
            echo "Unsupported option found: $1!"
            usage
            exit 3
            ;;
esac
done


section "Setup repo"
if  [[ "$REPOSITORY_SOURCE" != "network" ]];then
     echo "Setup local repo"
     setup_local_repo
else
echo "Setup online docker-ce repo"
cp ${CE_BASE}/OpenStackCE/rhel-repo/docker-ce.repo /etc/yum.repos.d/
section "Install docker-ce"
yum install -y yum-utils device-mapper-persistent-data lvm2
cd ${CE_BASE}/OpenStackCE/rhel-repo/x86_64/docker-ce/repo/main/redhat/7/
yum install -y container-selinux-2.74-1.el7.noarch.rpm
yum install -y docker-ce
start_docker
load_images
kill_containers
start_registry
start_repository
fi

section "Install epel"
cd ${CE_BASE}/OpenStackCE/rhel-repo
#yum install -y epel-release-latest-7.noarch.rpm 
check_status $? "Install epel"


section "Install net-tools to use ifconfig command"
yum install -y net-tools


section "Install git and pip"
yum install -y git python2-pip 1>/dev/null
pip install -U pip 1>/dev/null
check_status $? "Install git and pip"


section "Install kolla-ansible on deployment server"
yum install -y python-devel libffi-devel gcc openssl-devel libselinux-python python-libs ansible 1>/dev/null
check_status $? "Install depended packages and ansible"
pip install -U ansible 1>/dev/null
check_status $? "Upgrade ansible"
tee /etc/ansible/ansible.cfg 1>/dev/null << EOF
[defaults]
host_key_checking=False
pipelining=True
forks=100
EOF
check_status $? "Update ansible configuration file"
pip install --ignore-installed idna 1>/dev/null
check_status $? "Install idna"
current_dir=$(pwd) && cd ${CE_BASE}/OpenStackCE/kolla-ansible/ && pip install . 1>/dev/null && rc=$? && cd ${current_dir}
check_status $rc "Install kolla-ansible"


section "COPY configuration files to /etc/kolla"
suffix=`date +%Y%m%d`
cp -rf /etc/kolla /etc/kolla.bk${suffix} 2>/dev/null
rm -rf /etc/kolla 2>/dev/null
check_status $? "Backup old /etc/kolla if exists"
cp -rf ${CE_BASE}/OpenStackCE/kolla-ansible/etc/kolla /etc/
check_status $? "Copy /etc/kolla files"
cp ${CE_BASE}/OpenStackCE/kolla-ansible/ansible/inventory/* /etc/kolla/
check_status $? "Copy inventory files to /etc/kolla/"
mkdir -p /etc/kolla/config/nova
tee /etc/kolla/config/nova/nova-compute.conf 1>/dev/null << EOF
[DEFAULT]
enable_apis=osapi_compute,metadata
compute_driver=libvirt.LibvirtDriver
config_drive_format=iso9660
force_config_drive=True
firewall_driver=nova.virt.firewall.NoopFirewallDriver
pointer_model=ps2mouse
[vnc]
enabled=False
[libvirt]
virt_type=kvm
cpu_mode=none
inject_partition=-2
EOF
check_status $? "Add nova-compute.conf into /etc/kolla/config/nova/"


section "Generate Script used to setup target nodes"
if  [[ "$REPOSITORY_SOURCE" != "network" ]];then
     sources_x86=$(cat ${CE_BASE}/OpenStackCE/bootstrap_files_rhel/local-yum.repo.x86)
     sources_s390x=$(cat ${CE_BASE}/OpenStackCE/bootstrap_files_rhel/local-yum.repo.s390x)
     pip_conf=$(cat ${CE_BASE}/OpenStackCE/bootstrap_files_rhel/pip.conf)
     tee /etc/kolla/openstack-ce-presetups.sh 1>/dev/null << EOF
#!/bin/bash
node_arch=\$(arch)
if [ \${node_arch} == 'x86_64' ]; then
   echo "${sources_x86}" > /etc/yum.repos.d/local-yum.repo
   echo "Install epel rpm on x86 rhel"
   yum install -y wget
   wget http://SERVER:REPO_PORT/epel-release-latest-7.noarch.rpm
   yum install -y epel-release-latest-7.noarch.rpm
else
    echo "${sources_s390x}" > /etc/yum.repos.d/local-yum.repo
    yum install -y wget
    wget http://SERVER:REPO_PORT/s390x/docker-18.06.1-ce.tgz
    wget http://SERVER:REPO_PORT/s390x/docker.service
    wget http://SERVER:REPO_PORT/s390x/docker.socket
    tar xzvf docker-18.06.1-ce.tgz
    cp docker/* /usr/bin/
    cp docker.service /etc/systemd/system/
    cp docker.socket /etc/systemd/system/

    echo "Install epel rpm on s390x rhel"
    wget http://SERVER:REPO_PORT/epel-release-latest-7.noarch.rpm
    yum install -y epel-release-latest-7.noarch.rpm
    mv /etc/yum.repos.d/epel*.repo /etc/yum.repos.d/epel*.repo.bak
fi
echo "Setup pip.conf"
mkdir -p \${HOME}/.pip/
echo "${pip_conf}" > \${HOME}/.pip/pip.conf
EOF
else
tee /etc/kolla/openstack-ce-presetups.sh 1>/dev/null << EOF
#!/bin/bash
node_arch=\$(arch)
if [ \${node_arch} == 'x86_64' ]; then
   echo "Install epel rpm on x86 rhel"
   yum install -y wget
   wget http://SERVER:REPO_PORT/epel-release-latest-7.noarch.rpm
   yum install -y epel-release-latest-7.noarch.rpm
else
    echo "Install docker binary on s390x rhel"
    yum install -y wget
    wget http://SERVER:REPO_PORT/s390x/docker-18.06.1-ce.tgz
    wget http://SERVER:REPO_PORT/s390x/docker.service
    wget http://SERVER:REPO_PORT/s390x/docker.socket
    tar xzvf docker-18.06.1-ce.tgz
    cp docker/* /usr/bin/
    mv docker.service /etc/systemd/system/
    mv docker.socket /etc/systemd/system/

    echo "Install epel rpm on s390x rhel"
    wget http://SERVER:REPO_PORT/epel-release-latest-7.noarch.rpm
    yum install -y epel-release-latest-7.noarch.rpm
    mv /etc/yum.repos.d/epel.repo /etc/yum.repos.d/epel.repo.bak
    mv /etc/yum.repos.d/epel-testing.repo /etc/yum.repos.d/epel-testing.repo.bak
fi
EOF
fi
    sed -i "s/SERVER:REPO_PORT/${server_ip}:${REPOSITORY_PORT}/g" /etc/kolla/openstack-ce-presetups.sh
    chmod +x /etc/kolla/openstack-ce-presetups.sh
    check_status $?


section "Update globals.yml with the local docker registry and docker repo info"
sed -i "s/LOCAL_DOCKER_REGISTRY/${server_ip}:${DOCKER_REGISTRY_PORT}/g" /etc/kolla/globals.yml
check_status $? "Update docker registry info"
if  [[ "$REPOSITORY_SOURCE" != "network" ]];then
    echo "Update globals.yml with the local docker repo"
    sed -i'' -e 's/^#\(docker_yum_url\)/\1/g' /etc/kolla/globals.yml
    sed -i "s/DOCKER_YUM_REPO/${server_ip}:${REPOSITORY_PORT}\/x86_64\/docker-ce/g" /etc/kolla/globals.yml
    check_status $? "Update local docker repo"
fi
echo ""
echo "*********************************"
echo "All setups finished Successfully!"
echo "*********************************"
exit 0
