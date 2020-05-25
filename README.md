# ocp4upc
OCP4 Upgrade Paths Checker
## Description
This is just a bash script that generates a graphical output of the possible **minor upgrade paths** using production-ready **stable** and **fast** [OpenShift 4 channels](https://docs.openshift.com/container-platform/4.4/updating/updating-cluster-between-minor.html#understanding-upgrade-channels_updating-cluster-between-minor).
## Usage
~~~
$ ./ocp4upc.sh
-------------------------------------------------------------------
OCP4 Upgrade Paths Checker (stable & fast channels) v2.1

Usage:
./ocp4upc.sh source_version [arch]

Source Version:
4.x        Extract same-minor complete default channels  (e.g. 4.2)
4.x.z      Generate next-minor channels upgrade paths (e.g. 4.2.26)

Arch:
amd64      x86_64 (default)
s390x      IBM System/390
ppc64le    POWER8 little endian
-------------------------------------------------------------------
~~~
## Example
~~~
$ ./ocp4upc.sh 4.2.27
[INFO] Checking prerequisites (curl jq dot)... [OK] 
[INFO] Errata provided (4.x.z mode), targeting '4.3' channels for upgrade path generation.
[INFO] Checking if '4.2.27' (amd64) is a valid release... [OK] 
[INFO] Result exported as 'stable-4.3_amd64_20200526.svg'
[INFO] Result exported as 'fast-4.3_amd64_20200526.svg'
~~~
[image=[src="examples/fast-4.3_amd64_20200526.png", alt="fast-4.3 upgrade paths example (20200526)", size="LG - Large", data-cp-size="100%", data-cp-align="center",  ]]
## Dependencies
- `curl` <https://curl.haxx.se/>
- `jq` <http://stedolan.github.io/jq/>
- `dot` <http://www.graphviz.org/>
## Additional notes
For more info on how to perform a minor upgrade using [`oc`](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/) cli, please refer to this [solution](https://access.redhat.com/solutions/4606811) (subscription needed).
