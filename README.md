# ocp4upc
OpenShift4 (OCP4) Upgrade Paths Checker

## Description
This is a BASH script that generates a graphical output of the possible OpenShift4 **minor upgrade paths** using "stable", "fast" and "eus" production-ready [channels](https://docs.openshift.com/container-platform/4.6/updating/updating-cluster-between-minor.html#understanding-upgrade-channels_updating-cluster-between-minor).

**NOTE**: there is also a "candidate" channel that shouldn't be used for production purposes, if you want the script to also contemplate that one, simply modify `CHANDEF` variable in this [line](https://github.com/pamoedom/ocp4upc/blob/master/ocp4upc.sh#L8) and include it.

## Installation
~~~
$ git clone git@github.com:pamoedom/ocp4upc.git
$ ln -s ${PWD}/ocp4upc/ocp4upc.sh ~/bin/ocp4upc
~~~

**NOTE**: on this manner the upgrade is as simple as `git pull` within the local repository.

## Usage
~~~
$ ocp4upc
-----------------------------------------------------------------
OCP4 Upgrade Paths Checker (stable fast eus) v3.2

Usage:
/home/pamoedo/bin/ocp4upc <release/mode> [arch]

Release/Mode (mandatory):
4.x        Extract default graphs using same-minor channels
4.x.z      Generate upgrade paths using next-minor channels
4.x.z.     Generate upgrade paths using same-minor channels
4.x.z-4.y  Generate upgrade paths using multi-minor channels

Arch (optional):
amd64      x86_64 (default)
s390x      IBM System/390
ppc64le    POWER8/9 little endian
-----------------------------------------------------------------
~~~

## Examples
~~~
$ ocp4upc.sh 4.6.15
[INFO] Checking prerequisites (curl jq dot)... [SUCC] 
[INFO] Checking if '4.6.15' (amd64) is a valid release... [SUCC] 
[INFO] Detected mode '4.x.z', targeting channels '4.7' for upgrade path generation.
[WARN] Skipping channel 'eus-4.7_amd64', it's empty.
[WARN] Skipping channel 'stable-4.7_amd64', version not found.
[INFO] Result exported as 'fast-4.7_4.6.15_amd64_20210316.svg'
~~~
![fast-4.7](https://github.com/pamoedom/ocp4upc/blob/master/examples/fast-4.7_4.6.15_amd64_20210316.png)

~~~
$ ocp4upc.sh 4.1.34-4.7
[INFO] Checking prerequisites (curl jq dot)... [SUCC] 
[INFO] Checking if '4.1.34' (amd64) is a valid release... [SUCC] 
[INFO] Detected mode '4.x.z-', targeting channels '4.2 4.3 4.4 4.5 4.6 4.7' for multigraph generation.
[INPT] Select channel from [stable fast eus], press Enter for default value (stable): 
[INPT] Select max depth between [1-9], press Enter for default value (2): 
[WARN] Targeting '6' diff minor versions with '2' releases per target (12 edges), please be patient.
[INFO] Processing 'stable-4.2' edges... 
[INFO] Processing 'stable-4.3' edges... 
[INFO] Processing 'stable-4.4' edges... 
[INFO] Processing 'stable-4.5' edges... 
[INFO] Processing 'stable-4.6' edges... 
[INFO] Processing 'stable-4.7' edges... 
[WARN] Skipping file 'stable-4.7_4.6.19.gv', version not found.
[INFO] Result exported as 'stable-multigraph_4.1.34-4.7_amd64_20210316.svg'
~~~
![stable-multigraph-4.1](https://github.com/pamoedom/ocp4upc/blob/master/examples/stable-multigraph_4.1.34-4.7_amd64_20210316.png)

## Dependencies
- [`curl`](https://curl.haxx.se/)
- [`jq`](http://stedolan.github.io/jq/)
- [`dot`](http://www.graphviz.org/)

## Additional notes
For more info on how to perform a minor upgrade using [`oc`](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/) cli, please refer to this [solution](https://access.redhat.com/solutions/4606811) (subscription needed).
