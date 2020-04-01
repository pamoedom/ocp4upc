# ocp4upc
OCP4 Upgrade Paths Checker
## Description
This is a script to check the possible minor upgrade paths using production-ready OpenShift 4 **stable** and **fast**_ [channels](https://docs.openshift.com/container-platform/4.3/updating/updating-cluster-between-minor.html#understanding-upgrade-channels_updating-cluster-between-minor).
## Usage
~~~
$ ./ocp4upc.sh source_version [arch]
~~~
## Dependencies
- `curl` <https://curl.haxx.se/>
- `jq` <http://stedolan.github.io/jq/>
- `dot` <http://www.graphviz.org/>
- `skopeo` <https://github.com/containers/skopeo>
## Additional notes
For more info on how to perform a minor upgrade using `oc` cli, please refer to this [solution](https://access.redhat.com/solutions/4606811) (subscription needed).
