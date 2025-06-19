pipeline {
  agent any
  stages {
    stage('Clone Repo') {
      steps {
        git 'https://github.com/ritikkumar8434/Kubernetes-Kubeadm-configuration.gitt'
      }
    }
    stage('Run Ansible') {
      steps {
        sh 'ansible-playbook deploy-httpd.yaml -i inventory.ini'
      }
    }
  }
}
