# Kubernetes Cluster with Jenkins + Ansible on RHEL using Kubeadm

This project sets up a Kubernetes cluster manually using `kubeadm` on Red Hat Enterprise Linux (RHEL) nodes and deploys Jenkins and Ansible as pods to automate CI/CD tasks.

## Prerequisites
- RHEL 9 (1 master + worker nodes)
- Minimum 2 cpus and 2 Gb Ram
- Docker with cri-dockerd
- kubeadm, kubelet, kubectl installed
- Swap disabled
- Add 6443 port number in inbound rules of security groups

## Steps

### Prerequisites on All Nodes
```bash
# Disable swap (required for kubeadm)
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab

# Enable required kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF

sudo modprobe br_netfilter

# Set sysctl parameters
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

sudo sysctl --system
```



### Install Docker (Recommended with CLI Plugin)
```bash
sudo yum remove -y docker docker-client docker-client-latest docker-common docker-latest \
  docker-latest-logrotate docker-logrotate docker-engine

sudo yum install -y yum-utils device-mapper-persistent-data lvm2

sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

```
### Configure Docker to Use systemd CGroup Driver (for Kubernetes)
```bash
sudo mkdir -p /etc/docker

cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable --now docker

```
### Install cri-dockerd
```bash
sudo yum install -y wget tar
yum install git
cd /tmp
wget https://go.dev/dl/go1.23.10.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.23.10.linux-amd64.tar.gz
echo "export PATH=\$PATH:/usr/local/go/bin" >> ~/.bashrc
source ~/.bashrc
go version
```

### Install Kubernetes Tools
```bash
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
# This overwrites any existing configuration in /etc/yum.repos.d/kubernetes.repo
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.33/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.33/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

sudo dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
sudo systemctl enable --now kubelet
```

### Clone and Build cri-dockerd
```bash
git clone https://github.com/Mirantis/cri-dockerd.git
cd cri-dockerd
mkdir -p bin
go build -o bin/cri-dockerd

```
### Install Binary
```bash
sudo cp bin/cri-dockerd /usr/local/bin/

```
### Install systemd Service for cri-dockerd
```bash
sudo cp -a packaging/systemd/* /etc/systemd/system/

# Fix binary path in systemd service
sudo sed -i 's:/usr/bin/cri-dockerd:/usr/local/bin/cri-dockerd:' /etc/systemd/system/cri-docker.service

```


### Start and Enable cri-dockerd
```bash
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable cri-docker.service
sudo systemctl enable cri-docker.socket
sudo systemctl start cri-docker.socket
sudo systemctl start cri-docker.service

```

### Initialize Cluster (Master)
```bash
sudo kubeadm init --pod-network-cidr=192.168.0.0/16   --cri-socket=unix:///var/run/cri-dockerd.sock

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### Install Calico CNI
```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml
```

### If calico not installed from the github:
```
curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.25.1/manifests/calico.yaml
kubectl apply -f calico.yaml
```

### Generate a token for worker nodes to join:
```bash
 kubeadm token create --print-join-command
```
 
### Expose port 6443 in the Security group for the Worker to connect to Master Node

### Worker Node (Only):
```bash
#Run the following commands on the worker node
sudo kubeadm reset pre-flight checks

'''paste the join command you got from the master node and append --v=5 at the end. Make sure either you are working as sudo user or usesudo before the command'''

sudo kubeadm join <MASTER_IP>:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<CA_HASH> \
  --cri-socket=unix:///var/run/cri-dockerd.sock

```

### Verify if it is working as expected(master-node)!
```bash
kubectl get nodes
```


## Jenkins & Ansible Setup
```bash
#Dockerfile
# Base Jenkins image
FROM jenkins/jenkins:lts

# Switch to root to install tools
USER root

# Install Docker, Ansible, SSH
RUN apt update && \
    apt install -y docker.io ansible sshpass && \
    usermod -aG docker jenkins

# Return to Jenkins user
USER jenkins
```
### Build the Image and push it to the DockerHub:
```bash
docker build -t <your-dockerhub-username>/jenkins-ansible:v1 .
docker push <your-dockerhub-username>/jenkins-ansible:v1

```



### Deploy Jenkins
```bash
kubectl apply -f jenkins-pv.yaml
kubectl apply -f jenkins-pvc.yaml
kubectl apply -f jenkins-deployment.yaml
```
```cpp
http://<NodeIP>:30080
```

### Deploy Ansible Pod(optional)
```bash
kubectl apply -f ansible-pod.yaml
```

### Unlock Jenkins with initial admin password:
```bash
kubectl exec -it <jenkins-pod-name> -- cat /var/jenkins_home/secrets/initialAdminPassword

```

### Configuring Jenkins with necessary plugins
- Install plugins:
    - Docker, Ansible, SSH Pipeline Steps
```bash
#jenkinsfile
pipeline {
  agent any
  stages {
    stage('Clone Repo') {
      steps {
        git 'https://github.com/<your-repo>/devops-playbooks.git'
      }
    }
    stage('Run Ansible') {
      steps {
        sh 'ansible-playbook playbook.yaml -i inventory.ini'
      }
    }
  }
}



```
### Configuring Pods with Ansible(could be jenkins or ansible or both)
```bash
kubectl exec -it <pod-name> -- bash
ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -q -N ""
ssh-copy-id -i ~/.ssh/id_rsa.pub root@<node-ip>
```
### Repeat this for:

- Master node (except Jenkins pod if it's on master)

- All worker nodes


### Ansible Inventory & Config
Edit `inventory.ini` and `ansible.cfg` for your cluster.

### Sample playbook- deploy.yml

## File Structure

```
.
├── README.md
├── Dockerfile
├── ansible.cfg
├── inventory.ini
├── ansible-pod.yaml
├── jenkins-deployment.yaml
├── jenkins-pv.yaml
├── jenkins-pvc.yaml
├── Jenkinsfile
├── deploy-http.yml

```

---

Developed by Ritik Kumar Sahu 🚀
