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
-------------------------------------------------------------------
OCP4 Upgrade Paths Checker (stable fast eus) v3.0

Usage:
/home/pamoedo/bin/ocp4upc version [arch]

Version/Mode:
4.x        Extract default graphs using same-minor channels
4.x.z      Generate upgrade paths using next-minor channels
4.x.z.     Generate upgrade paths using same-minor channels
4.x.z-4.y  Generate upgrade paths using multi-minor channels (experimental)

Arch (optional):
amd64      x86_64 (default)
s390x      IBM System/390
ppc64le    POWER8/9 little endian
-------------------------------------------------------------------
~~~

## Examples
~~~
$ ocp4upc 4.5.20
[INFO] Checking prerequisites (curl jq dot)... [SUCC] 
[INFO] Checking if '4.5.20' (amd64) is a valid release... [SUCC] 
[INFO] Detected mode '4.x.z', targeting channels '4.6' for upgrade path generation.
[WARN] Skipping channel 'eus-4.6_amd64', version not found.
[INFO] Result exported as 'stable-4.6_4.5.20-amd64_20210207.svg'
[INFO] Result exported as 'fast-4.6_4.5.20-amd64_20210207.svg'
~~~
![fast-4.6](https://github.com/pamoedom/ocp4upc/blob/master/examples/fast-4.6_4.5.20-amd64_20210207.png)

~~~
$ ocp4upc 4.2.26-4.6
[INFO] Checking prerequisites (curl jq dot)... [SUCC] 
[INFO] Checking if '4.2.26' (amd64) is a valid release... [SUCC] 
[INFO] Detected mode '4.x.z-', targeting channels '4.3 4.4 4.5 4.6' for multigraph generation.
[WARN] This is an EXPERIMENTAL mode targeting only 2 latest releases per channel.
[INPT] Select channel type from the list [stable fast eus]: stable
[INFO] Processing 'stable-4.3' edges... 
[INFO] Processing 'stable-4.4' edges... 
[INFO] Processing 'stable-4.5' edges... 
[INFO] Processing 'stable-4.6' edges... 
[WARN] Skipping file 'stable-4.6_4.5.30.gv', no upgrade paths available.
[INFO] Result exported as 'stable-multigraph_4.2.26-4.6_20210207.svg'
~~~
![stable-multigraph-4.6](https://github.com/pamoedom/ocp4upc/blob/master/examples/stable-multigraph_4.2.26-4.6_20210207.png)

## Dependencies
- [`curl`](https://curl.haxx.se/)
- [`jq`](http://stedolan.github.io/jq/)
- [`dot`](http://www.graphviz.org/)

## Additional notes
For more info on how to perform a minor upgrade using [`oc`](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/) cli, please refer to this [solution](https://access.redhat.com/solutions/4606811) (subscription needed).
