#!/bin/sh
VERSION="1.0"

#INFO = (
#          author      => 'Pedro Amoedo'
#          contact     => 'pamoedom@redhat.com'
#          name        => 'ocp4upc.sh',
#          usage       => '(see below)',
#          description => 'OCP4 Upgrade Paths Checker',
#       );

#CHANGELOG = (
#              * v1.0
#                - Initial commit
#            );

#VARs DESCRIPTION
#$1=current_release
#$2=arch (optional, default = amd64)

#ANSI COLORS
OK="echo -en \\033[1;32m"
ERROR="echo -en \\033[1;31m"
WARN="echo -en \\033[1;33m"
INFO="echo -en \\033[1;34m"
NORM="echo -en \\033[0;39m"

usage(){
  echo "OCP4 Upgrade Paths Checker (stable,fast) v${VERSION}"
  echo "---------------------------------------------"
  echo "Usage: $0 source_version [arch]"
  echo "---------------------------------------------"
  exit 1
}

#Pretty Print function ($type_of_msg,$string,$echo_opts)
cout(){
  echo -n "[" && eval "\$$1" && echo -n "$1" && $NORM && echo -n "] " && echo $3 "$2"
}

#VARIABLES
[[ $# -lt 1 ]] && usage
URL='api.openshift.com/api/upgrades_info/v1/graph'
VER=$1
MAJ=`echo ${VER} | cut -d. -f1`
MIN=`echo ${VER} | cut -d. -f2`
TRG="${MAJ}.`echo ${MIN}+1 | bc`"
EDG="blue"
ORG="salmon"
DST="yellowgreen"
[[ -z $2 ]] && ARC="amd64" || ARC=$2
POS=""
PTH="/tmp/${0##*/}"
BIN="/usr/bin"
CHA=(stable fast)
REQ=(curl skopeo jq dot)
RES=()
LTS=""

#PREREQUISITES
cout "INFO" "Checking prerequisites... " "-n"
for tool in ${REQ[@]}; do ${BIN}/which $tool &>/dev/null; [ $? -ne 0 ] && cout "ERROR" "'$tool' not present. Aborting" && exit 1; done
if [ -d ${PTH} ]
  then
    ${BIN}/touch ${PTH}/test; [ $? -ne 0 ] && cout "ERROR" "Unable to write in ${PTH}. Aborting" && exit 1
  else
    ${BIN}/mkdir ${PTH}; [ $? -ne 0 ] && cout "ERROR" "Unable to write in ${PTH}. Aborting" && exit 1
fi
cout "OK" ""

## TODO: Do this with curl against the API to avoid installing skopeo?
cout "INFO" "Checking if '${VER}' (${ARC}) is a valid release... " "-n"
if [ "${ARC}" = "amd64" ]
  then
    ${BIN}/skopeo inspect docker://quay.io/openshift-release-dev/ocp-release:${VER}-x86_64 &>/dev/null
    # for amd64 make an extra attempt without -x86_64 because old releases do not contain that suffix
    if [ $? -ne 0 ]
      then
        ${BIN}/skopeo inspect docker://quay.io/openshift-release-dev/ocp-release:${VER} &>/dev/null; [ $? -ne 0 ] && cout "ERROR" "" && exit 1
    fi
  else
    ${BIN}/skopeo inspect docker://quay.io/openshift-release-dev/ocp-release:${VER}-${ARC} &>/dev/null; [ $? -ne 0 ] && cout "ERROR" "" && exit 1
fi
cout "OK" ""

#OBTAIN JSON
for chan in ${CHA[@]}; do ${BIN}/curl -sH 'Accept:application/json' "https://${URL}?channel=${chan}-${TRG}&arch=${ARC}" > ${PTH}/${chan}-${TRG}.json; [ $? -ne 0 ] && cout "ERROR" "Unable to curl 'https://${URL}?channel=${chan}-${TRG}&arch=${ARC}'. Aborting" && exit 1; done

##capture the latest target version within fast channel (TODO: do this against the API directly?)
LTS=`${BIN}/cat ${PTH}/fast-${TRG}.json | ${BIN}/jq . | ${BIN}/grep "\"${TRG}." | ${BIN}/cut -d'"' -f4 | ${BIN}/sort -urV | ${BIN}/head -1`

#JSON to GV
JQ_SCRIPT='"digraph TITLE {\n  labelloc=t;\n  rankdir=BT;\n  label=CHANNEL" as $header |
  (
    [
      .nodes |
      to_entries[] |
      "  " + (.key | tostring) +
             " [ label=\"" + .value.version + "\"" + (
               if .value.metadata.url then ",url=\"" + .value.metadata.url + "\"" else "" end
             ) + (
	       if .value.version == "'"${VER}"'" then ",shape=polygon,sides=5,peripheries=3,style=filled,color='"${ORG}"'"
	       elif .value.version == "'"${LTS}"'" then ",shape=square,style=filled,color='"${DST}"'"
	       elif .value.version >= "'"${TRG}"'" then ",shape=square,style=filled,color=lightgrey"
	       else ",shape=ellipse,style=filled,color=lightgrey"
	       end
	     ) +
             " ];"
    ] | join("\n")
  ) as $nodes |
  (
    [
      .edges[] |
      "  " + (.[0] | tostring) + "->" + (.[1] | tostring) + ";"
    ] | join("\n")
  ) as $edges |
  [$header, $nodes, $edges, "}"] | join("\n")
'
for chan in ${CHA[@]}; do ${BIN}/jq -r "${JQ_SCRIPT}" ${PTH}/${chan}-${TRG}.json > ${PTH}/${chan}-${TRG}.gv; done

#DISCARD CHANNELS & COLORIZE EDGES
for chan in ${CHA[@]}
do
  POS="" && POS=`grep ${VER} ${PTH}/${chan}-${TRG}.gv | awk {'print $1'}`
  if [ "${POS}" = "" ]
    then
     cout "WARN" "Skipping channel '${chan}-${TRG}', version '${VER}' not found."
    else
      sed -i -e 's/^\s\s'"${POS}"'\(->.*$\)/  edge \[color='"${EDG}"'\,style=bold];\n  '"${POS}"'\1\ \n  edge \[color=black\,style=solid];/g' ${PTH}/${chan}-${TRG}.gv
      RES=("${RES[@]}" "${chan}")
  fi
done

[[ ${#RES[@]} -eq 0 ]] && cout "ERROR" "Version '${VER}' not found within any of the ${TRG} channels. Aborting" && exit 1

#LABELING
for chan in ${RES[@]}; do sed -i -e 's/TITLE/'"${chan}"'/g' ${PTH}/${chan}-${TRG}.gv; done
for chan in ${RES[@]}; do sed -i -e 's/CHANNEL/"'"${chan}"'-'"${TRG}"'"/g' ${PTH}/${chan}-${TRG}.gv; done

#DRAW & EXPORT
for chan in ${RES[@]}; do ${BIN}/dot -Tsvg ${PTH}/${chan}-${TRG}.gv -o ${chan}-${TRG}.svg; [ $? -ne 0 ] && cout "ERROR" "Unable to export the results. Aborting" && exit 1 || cout "INFO" "Result exported as '${chan}-${TRG}.svg'"; done

#EOF
exit 0
