#!/bin/bash -ex

gcloud compute networks create 'kube-net' \
  --range '192.168.0.0/16'

gcloud compute firewall-rules create 'kube-extfw' \
  --network 'kube-net' \
  --allow 'tcp:22,tcp:4040' \
  --target-tags 'kube-ext' \
  --description 'External access for SSH and Weave Scope user interface'

gcloud compute firewall-rules create 'kube-intfw' \
  --network 'kube-net' \
  --allow 'tcp:6783,udp:6783-6784' \
  --source-ranges '192.168.0.0/16' \
  --target-tags 'kube-weave' \
  --description 'Internal access for Weave Net ports'

gcloud compute firewall-rules create 'kube-nodefw' \
  --network 'kube-net' \
  --allow 'tcp,udp,icmp,esp,ah,sctp' \
  --source-ranges '192.168.0.0/16' \
  --target-tags 'kube-node' \
  --description 'Internal access to all ports on the nodes'

## However, it'd be hard to decide which of the instances in a managed
## group should run `etcd1`, `etcd2` or `etcd3`. Hence the etcd nodes and
## master are be part of an unmanaged instance group and thereby
## retain predefined hostnames. With Kubernetes 1.2 and the leader election
## feature we might move master nodes into a managed group.

gcloud compute instance-groups unmanaged create 'kube-master-group'

gcloud compute instances create $(seq -f 'kube-etcd-%g' 1 3) \
  --network 'kube-net' \
  --tags 'kube-weave,kube-ext' \
  --image 'debian-8' \
  --metadata-from-file 'startup-script=provision.sh' \
  --boot-disk-type 'pd-standard' \
  --boot-disk-size '20GB' \
  --scopes 'compute-ro'

gcloud compute instances create 'kube-master-0' \
  --network 'kube-net' \
  --tags 'kube-weave,kube-ext' \
  --image 'debian-8' \
  --metadata-from-file 'startup-script=provision.sh' \
  --boot-disk-type 'pd-standard' \
  --boot-disk-size '10GB' \
  --can-ip-forward \
  --scopes 'storage-ro,compute-rw,monitoring,logging-write'

gcloud compute instance-groups unmanaged add-instances 'kube-master-group' \
  --instances $(seq -f 'kube-etcd-%g' 1 3) 'kube-master-0'

gcloud compute instance-templates create 'kube-node-template' \
  --network 'kube-net' \
  --tags 'kube-weave,kube-ext,kube-node' \
  --image 'debian-8' \
  --metadata-from-file 'startup-script=provision.sh' \
  --boot-disk-type 'pd-standard' \
  --boot-disk-size '30GB' \
  --can-ip-forward \
  --scopes 'storage-ro,compute-rw,monitoring,logging-write'

gcloud compute instance-groups managed create 'kube-node-group' \
  --template 'kube-node-template' \
  --base-instance-name 'kube-node' \
  --size 3
