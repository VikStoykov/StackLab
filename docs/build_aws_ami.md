# How to build AWS AMI

This is part of 'Configuration management'

## Tools

__EC2__ — Amazon Elastic Compute Cloud is a part of Amazon.com’s cloud-computing platform, Amazon Web Services, that allows users to rent virtual computers on which to run their own computer applications. [Wikipedia]

__Ansible__ — Ansible is a suite of software tools that enables infrastructure as code. It is open-source and the suite includes software provisioning, configuration management, and application deployment functionality. [Wikipedia]

![Alt text](/images/ansible_aws.png)

## Process Steps

1. Prepare AWS Account
2. Install required software on local computer
3. Setup Non Ansible Local Files — Project Directory, SSH Keys
4. Setup Ansible vault or Hashicorp vault
5. Setup Ansible playbooks
6. Setup init script
7. Run Ansible playbook

### 1. Prepare AWS Account

If you already have an IAM user with an Access/Secret Access key and EC2 permissions, you can skip this step and proceed to installing the required software on your local computer.

#### Creating an IAM user

To provision EC2 instances, you'll need an AWS account with an IAM user at a minimum. Create one through AWS Console > IAM > Add User, as shown below:
![Alt text](/images/create_iam_user.png)

This is our group:
![Alt text](/images/ami_user_group.png)

and roles to it:
![Alt text](/images/ami_user_group_roles.png)

### 2. Install required software on local computer

Software is needed on your local computer, if they are already installed, skip this step and start preparing your project directory. The software required includes:

* Python 3.10.12
* pip3
* boto (via pip)
* boto3 (via pip)
* [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)

Required by AWS Ansible module for Ansible:

```bash
# ansible-galaxy collection install amazon.aws
Starting galaxy collection install process
Process install dependency map
Starting collection install process
Installing 'amazon.aws:7.2.0' to '/home/victor/.ansible/collections/ansible_collections/amazon/aws'
Downloading https://galaxy.ansible.com/api/v3/plugin/ansible/content/published/collections/artifacts/amazon-aws-7.2.0.tar.gz to /home/victor/.ansible/tmp/ansible-local-386246rx621fil/tmpm_s0m66v
amazon.aws (7.2.0) was installed successfully
```

### 3. Setup Non Ansible Local Files — Project Directory, SSH Keys

#### Generate SSH keys

Generate SSH keys (to SSH into provisioned EC2 instances) with this command:

1. This creates a public (.pub) and private key in the ~/.ssh/ directory
```# ssh-keygen -t rsa -b 4096 -f ~/.ssh/my_aws```
_Generating public/private rsa key pair.
Enter passphrase (empty for no passphrase):
Enter same passphrase again:
Your identification has been saved in /home/victor/.ssh/my_aws
Your public key has been saved in /home/victor/.ssh/my_aws.pub
The key fingerprint is:
SHA256:b7d4bbuVesjW6iBYn9ZCp7p9lyDwp1Y5Hauh/zyO2rU victor@victors-ubuntu
The key's randomart image is:
+---[RSA 4096]----+_

2. Ensure private key is not publicly viewable
```chmod 400 ~/.ssh/my_aws```

### 4. Setup Ansible vault or Hashicorp vault (2 methods)

#### Method 1: Manually enter password

1. Create an ansible vault
```ansible-vault create automation/ansible/group_vars/all/pass.yml```

2. There's a prompt for a password, it's needed for playbook execution/edit
_New Vault password:
Confirm New Vault password:_

With this method, you will be prompted for a password every time playbooks are executed or pass.yml is edited.

#### Method 2: Hashicorp vault

...

### 5. Setup Ansible playbooks

Change configuration to your fits in _/automation/ansible/playbook.yml_ :

```bash
  vars:
    key_name: my_aws             # Key used for SSH
    region: eu-west-1            # Region may affect response and pricing
    image: ami-0905a3c97561e0b69 # ec2 ubuntu ami (HVM)
    id: "OpenStack single node" # name/id of EC2
    instance_type: t3.xlarge     # Choose instance type, check AWS for pricing
    volume_size: 60              # Volume size in GB
    instance_name: OpenStack cluster- AMI # Name of instance
    ami_name: openstack_sigle_node_ami # AMI name
    sec_group: "admin"           # Create Security Group in AWS
    ssh_user: ubuntu             # User
    ssh_key: /home/victor/.ssh/my_aws # Local SSH Key
```

### 6. Setup scripts

We use Canonical OpenStack's Sunbeam for deployment, which streamlines the OpenStack installation process. Our scripts automate the following key steps:

#### 6.1 Install OpenStack Snap

Our init scripts begin by installing the OpenStack snap, which includes the `sunbeam` command for bootstrapping and operating the cloud:

```bash
sudo snap install openstack
```

#### 6.2 Prepare the Machine

Before bootstrapping, the script prepares the machine by:
- Installing required dependencies (including openssh-server)
- Configuring passwordless sudo access for the current user
- Adding the user to the snap_daemon group for proper permissions

These tasks are automated with:

```bash
sunbeam prepare-node-script --bootstrap | bash -x && newgrp snap_daemon
```

#### 6.3 Bootstrap the Cloud

The main deployment script triggers a comprehensive bootstrap that:
- Installs Canonical OpenStack for hosting cloud control functions
- Installs Canonical Juju and bootstraps a controller
- Configures cloud control functions
- Installs and configures the OpenStack Hypervisor snap
- Installs and configures MicroCeph for storage

This is accomplished with:

```bash
sunbeam cluster bootstrap --accept-defaults --role control,compute,storage
```

#### 6.4 Configure the Cloud

After bootstrap, the script configures the cloud for immediate use by:
- Creating a demo user
- Populating the cloud with common templates
- Creating a sandbox project with basic configuration

```bash
sunbeam configure --accept-defaults --openrc demo-openrc
```

You can customize these scripts by modifying the roles in the bootstrap command to match your deployment needs. For instance, you might separate control and compute roles for production environments.

### 7. Run Ansible playbook

This process involves initiating an EC2 instance, installing OpenStack packages and modules, and generating an AWS Amazon Machine Image (AMI) from it.

To execute the playbook, use the following command:
```ansible-playbook playbook.yml --vault-password-file group_vars/all/pass.yml```

The resulting output will resemble:

```bash
PLAY [localhost] *********************************************************************************************************************************************************************************************
TASK [roles/instance_init : Create security group] ***********************************************************************************************************************************************************
ok: [localhost]

TASK [roles/instance_init : Amazon EC2 | Create Key Pair] ****************************************************************************************************************************************************
ok: [localhost]

TASK [roles/instance_init : Start an instance with a public IP address] **************************************************************************************************************************************
changed: [localhost]

TASK [roles/connect : Get instances facts] *******************************************************************************************************************************************************************
ok: [localhost]

TASK [roles/connect : Instance Info] *************************************************************************************************************************************************************************
ok: [localhost] => {
    "msg": "Tags: {'Environment': 'OpenStack', 'Name': 'OpenStack cluster- AMI'}ID: i-05480df7af53f2922 - State: pending - Public DNS: ec2-54-77-129-97.eu-west-1.compute.amazonaws.com"
}

TASK [roles/connect : Add new instance to host group] ********************************************************************************************************************************************************
ok: [localhost]

TASK [roles/connect : Wait for SSH to come up] ***************************************************************************************************************************************************************
ok: [localhost]

PLAY [Install K8S Cluster] ***********************************************************************************************************************************************************************************
TASK [Gathering Facts] ***************************************************************************************************************************************************************************************
ok: [54.77.129.97]

TASK [roles/k8s_installation : Copy init script for OpenStack] **********************************************************************************************************************************************
changed: [54.77.129.97]

TASK [roles/k8s_installation : Execute script] ***************************************************************************************************************************************************************
changed: [54.77.129.97]

TASK [roles/k8s_installation : debug] ************************************************************************************************************************************************************************
ok: [54.77.129.97] => {
    "script.stdout_lines": [
        "overlay ",
        "br_netfilter ",
        "net.bridge.bridge-nf-call-iptables  = 1 ",
        "net.bridge.bridge-nf-call-ip6tables = 1 ",
        "net.ipv4.ip_forward                 = 1 ",
        "* Applying /etc/sysctl.d/10-console-messages.conf ...",
        ...
        ...
        ...
        "[config/images] Pulled registry.k8s.io/kube-apiserver:v1.26.3",
        "[config/images] Pulled registry.k8s.io/kube-controller-manager:v1.26.3",
        "[config/images] Pulled registry.k8s.io/kube-scheduler:v1.26.3",
        "[config/images] Pulled registry.k8s.io/kube-proxy:v1.26.3",
        "[config/images] Pulled registry.k8s.io/pause:3.9",
        "[config/images] Pulled registry.k8s.io/etcd:3.5.6-0",
        "[config/images] Pulled registry.k8s.io/coredns/coredns:v1.9.3"
    ]
}

TASK [roles/k8s_installation : Check if init script successfully deployed] ***********************************************************************************************************************************
ok: [54.77.129.97]

TASK [roles/k8s_installation : Report if a 'ready' file exists] **********************************************************************************************************************************************
ok: [54.77.129.97] => {
    "msg": "The init script successfully deployed."
}

TASK [roles/k8s_installation : Report if a file exists] ******************************************************************************************************************************************************
skipping: [54.77.129.97]

PLAY [localhost] *********************************************************************************************************************************************************************************************
TASK [roles/ami_creation : Get instances facts] **************************************************************************************************************************************************************
ok: [localhost]

TASK [roles/ami_creation : Instance Info] ********************************************************************************************************************************************************************
ok: [localhost] => {
    "msg": "Tags: {'Environment': 'OpenStack', 'Name': 'OpenStack cluster- AMI'}ID: i-05480df7af53f2922 - State: running - Public DNS: ec2-54-77-129-97.eu-west-1.compute.amazonaws.com"
}

TASK [roles/ami_creation : AMI Creation] *********************************************************************************************************************************************************************
changed: [localhost]

TASK [roles/cleanup : Get instances facts] *******************************************************************************************************************************************************************
ok: [localhost]

TASK [roles/cleanup : Instance Info] *************************************************************************************************************************************************************************
ok: [localhost]  => {
    "msg": "Tags: {'Environment': 'OpenStack', 'Name': 'OpenStack cluster- AMI'}ID: i-03e826d7ae85785a0 - State: running - Public DNS: ec2-54-228-168-158.eu-west-1.compute.amazonaws.com"
}

TASK [roles/cleanup : Terminate EC2 instance] ****************************************************************************************************************************************************************
changed: [localhost] 

PLAY RECAP ***************************************************************************************************************************************************************************************************
54.228.168.158             : ok=6    changed=2    unreachable=0    failed=0    skipped=1    rescued=0    ignored=0   
localhost                  : ok=13   changed=3    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
```

EC2 instance:
![Alt text](/images/ec2_instance_ami.png)

AMI:
![Alt text](/images/ami.png)
