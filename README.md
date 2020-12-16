# ocp4upc
OpenShift4 (OCP4) Upgrade Paths Checker

## Description
This is a BASH script that generates a graphical output of the possible OpenShift4 **minor upgrade paths** using "stable", "fast" and "eus" production-ready [channels](https://docs.openshift.com/container-platform/4.6/updating/updating-cluster-between-minor.html#understanding-upgrade-channels_updating-cluster-between-minor).

**NOTE**: there is also a "candidate" channel that shouldn't be used for production purposes, if you want the script to also contemplate that one, simply modify `CHANDEF` variable in this [line](https://github.com/pamoedom/ocp4upc/blob/master/ocp4upc.sh#L8) and include it.

## Usage
~~~
$ ./ocp4upc.sh
-------------------------------------------------------------------
OCP4 Upgrade Paths Checker (stable fast eus) v2.8

Usage:
./ocp4upc.sh source_version [arch]

Source Version:
4.x        Extract default graphs using same-minor channels, e.g. '4.2'
4.x.z      Generate upgrade paths using next-minor channels, e.g. '4.2.26'
4.x.z.     Generate upgrade paths using same-minor channels, e.g. '4.2.26.'

Arch (optional):
amd64      x86_64 (default)
s390x      IBM System/390
ppc64le    POWER9 little endian
-------------------------------------------------------------------
~~~

## Example
~~~
$ ./ocp4upc.sh 4.5.20
[INFO] Checking prerequisites (curl jq dot)... [OK] 
[INFO] Errata provided (4.x.z mode), targeting '4.6' channels for upgrade path generation.
[INFO] Checking if '4.5.20' (amd64) is a valid release... [OK] 
[WARN] Skipping channel 'stable-4.6_amd64', version '4.5.20' not found.
[WARN] Skipping channel 'eus-4.6_amd64', version '4.5.20' not found.
[INFO] Result exported as 'fast-4.6_amd64_20201216.svg'
~~~
![fast-4.6](https://github.com/pamoedom/ocp4upc/blob/master/examples/fast-4.6_amd64_20201216.png)

## Dependencies
- `curl` <https://curl.haxx.se/>
- `jq` <http://stedolan.github.io/jq/>
- `dot` <http://www.graphviz.org/>

## Additional notes
For more info on how to perform a minor upgrade using [`oc`](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/) cli, please refer to this [solution](https://access.redhat.com/solutions/4606811) (subscription needed).
