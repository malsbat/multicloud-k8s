# How to use this as a helm repo

```bash
$ helm repo add kud 'https://raw.githubusercontent.com/malsbat/multicloud-k8s/helm-addons/kud/deployment_infra/helm/charts'
$ helm repo update
$ helm search repo
NAME      	CHART VERSION	APP VERSION	DESCRIPTION
kud/multus	0.1.0        	v3.4.1-tp  	A CNI plugin for Kubernetes that enables attach...
kud/nfd   	0.1.0        	v0.4.0     	A Kubernetes add-on for detecting hardware feat...
```
