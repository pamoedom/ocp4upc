# ocp4upc
OCP4 Upgrade Paths Checker
## Description
This is just a bash script that generates a graphical output of the possible **minor upgrade paths** using production-ready **stable** and **fast** [OpenShift 4 channels](https://docs.openshift.com/container-platform/4.4/updating/updating-cluster-between-minor.html#understanding-upgrade-channels_updating-cluster-between-minor).
## Usage
~~~
$ ./ocp4upc.sh
---------------------------------------------------------
OCP4 Upgrade Paths Checker (stable & fast) v1.7

Usage:
/ocp4upc.sh source_version [arch]

Source Version:
4.x        Target same minor channels (B&W) (e.g. 4.2)
4.x.z      Target next minor channels (CLR) (e.g. 4.2.26)

Arch:
amd64      x86_64 (default)
s390x      IBM System/390
ppc64le    POWER8 little endian
---------------------------------------------------------
~~~
## Example
~~~
$ ./ocp4upc_test.sh 4.2.26
[INFO] Checking prerequisites... [OK] 
[INFO] Errata provided (4.x.z mode), targeting '4.3' channels.
[INFO] Checking if '4.2.26' (amd64) is a valid release... [OK] 
[INFO] Result exported as 'stable-4.3_amd64_20200518.svg'
[INFO] Result exported as 'fast-4.3_amd64_20200518.svg'
~~~
![fast-4.3 example](https://github.com/pamoedom/ocp4upc/blob/master/examples/fast-4.3_amd64_20200518.png)
## Dependencies
- `curl` <https://curl.haxx.se/>
- `jq` <http://stedolan.github.io/jq/>
- `dot` <http://www.graphviz.org/>
- `bc` <http://www.gnu.org/software/bc/>
## Additional notes
For more info on how to perform a minor upgrade using [`oc`](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/) cli, please refer to this [solution](https://access.redhat.com/solutions/4606811) (subscription needed).
