#!/bin/sh
VERSION="1.3"
BIN="/usr/bin"

#INFO = (
#          author      => 'Pedro Amoedo'
#          contact     => 'pamoedom@redhat.com'
#          name        => 'ocp4upc.sh',
#          usage       => '(see below)',
#          description => 'OCP4 Upgrade Paths Checker',
#       );

#CHANGELOG = (
#              * v1.3
#                - Fixing strict release parsing for ${POS}
#                - Enforcing ${BIN} path for all binaries
#                - ${LTS} for both channels
#                - Channels order swapped to properly match LTS
#                - Adding timestamp on exported files
#                - Colorize all edges reaching ${LTS}
#                - Some cosmetic changes
#              * v1.2
#                - Adding timestamp in the graph title (rfc-3339)
#                - Fixed prerequisites list (bc)
#              * v1.1
#                - Checking releases against quay API
#                - Removing skopeo prerequisite
#              * v1.0
#                - Initial commit
#            );

#VARs DESCRIPTION
#$1=current_release
#$2=arch (optional, default = amd64)

#ANSI COLORS
OK="${BIN}/echo -en \\033[1;32m"
ERROR="${BIN}/echo -en \\033[1;31m"
WARN="${BIN}/echo -en \\033[1;33m"
INFO="${BIN}/echo -en \\033[1;34m"
NORM="${BIN}/echo -en \\033[0;39m"

usage(){
  ${BIN}/echo "OCP4 Upgrade Paths Checker (fast,stable) v${VERSION}"
  ${BIN}/echo "---------------------------------------------"
  ${BIN}/echo "Usage: $0 source_version [arch]"
  ${BIN}/echo "---------------------------------------------"
  exit 1
}

#Pretty Print function ($type_of_msg,$string,$echo_opts)
cout(){
  ${BIN}/echo -n "[" && eval "\$$1" && ${BIN}/echo -n "$1" && $NORM && ${BIN}/echo -n "] " && ${BIN}/echo $3 "$2"
}

#VARIABLES
[[ $# -lt 1 ]] && usage
GPH='https://api.openshift.com/api/upgrades_info/v1/graph'
REL='https://quay.io/api/v1/repository/openshift-release-dev/ocp-release'
VER=$1
MAJ=`${BIN}/echo ${VER} | ${BIN}/cut -d. -f1`
MIN=`${BIN}/echo ${VER} | ${BIN}/cut -d. -f2`
TRG="${MAJ}.`${BIN}/echo ${MIN}+1 | ${BIN}/bc`"
EDG="blue"
EDGt="red"
ORG="salmon"
DST="yellowgreen"
[[ -z $2 ]] && ARC="amd64" || ARC=$2
POSv=""
POSc=""
PTH="/tmp/${0##*/}"
CHA=(fast stable) #The order here is relevant to colorize the LTS per channel, see JQ_SCRIPT below.
REQ=(curl jq dot bc)
RES=() #Array of resulting channels in case of discard.
LTS=() #Array of latest target releases per channel.
EXT=() #Array of indirect nodes

#PREREQUISITES

## all tools available?
cout "INFO" "Checking prerequisites... " "-n"
for tool in ${REQ[@]}; do ${BIN}/which $tool &>/dev/null; [ $? -ne 0 ] && cout "ERROR" "'$tool' not present. Aborting" && exit 1; done

## tmp folder writable?
if [ -d ${PTH} ]
  then
    ${BIN}/touch ${PTH}/test; [ $? -ne 0 ] && cout "ERROR" "Unable to write in ${PTH}. Aborting" && exit 1
  else
    ${BIN}/mkdir ${PTH}; [ $? -ne 0 ] && cout "ERROR" "Unable to write in ${PTH}. Aborting" && exit 1
fi
cout "OK" ""

## valid release?
cout "INFO" "Checking if '${VER}' (${ARC}) is a valid release... " "-n"
${BIN}/curl -sH 'Accept:application/json' "${REL}" | ${BIN}/jq . > ${PTH}/ocp4-releases.json
if [ "${ARC}" = "amd64" ]
  then
    ${BIN}/grep "\"${VER}-x86_64\"" ${PTH}/ocp4-releases.json &>/dev/null
    # for amd64 make an extra attempt without -x86_64 because old releases do not contain that suffix
    if [ $? -ne 0 ]
      then
        ${BIN}/grep "\"${VER}\"" ${PTH}/ocp4-releases.json &>/dev/null; [ $? -ne 0 ] && cout "ERROR" "" && exit 1
    fi
  else
    ${BIN}/grep "\"${VER}-${ARC}\"" ${PTH}/ocp4-releases.json &>/dev/null; [ $? -ne 0 ] && cout "ERROR" "" && exit 1
fi
cout "OK" ""

#OBTAIN UPGRADE PATHS JSONs
for chan in ${CHA[@]}; do ${BIN}/curl -sH 'Accept:application/json' "${GPH}?channel=${chan}-${TRG}&arch=${ARC}" > ${PTH}/${chan}-${TRG}.json; [ $? -ne 0 ] && cout "ERROR" "Unable to curl 'https://${GPH}?channel=${chan}-${TRG}&arch=${ARC}'. Aborting" && exit 1; done

##capture the latest target version within each channel (TODO: do this against the API?)
for chan in ${CHA[@]}; do LTS=("${LTS[@]}" "$(${BIN}/cat ${PTH}/${chan}-${TRG}.json | ${BIN}/jq . | ${BIN}/grep "\"${TRG}." | ${BIN}/cut -d'"' -f4 | ${BIN}/sort -urV | ${BIN}/head -1)"); done

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
	       elif .value.version == "'"${LTS[0]}"'" then ",shape=square,style=filled,color='"${DST}"'"
	       elif .value.version == "'"${LTS[1]}"'" then ",shape=square,style=filled,color='"${DST}"'"
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

#DISCARD CHANNELS & COLORIZE EDGES (TODO: move this logic into JQ_SCRIPT?)
for chan in ${CHA[@]}
do
  POSv="" && POSv=`grep "\"${VER}\"" ${PTH}/${chan}-${TRG}.gv | awk {'print $1'}`
  if [ "${POSv}" = "" ]
    then
      cout "WARN" "Skipping channel '${chan}-${TRG}', version '${VER}' not found."
    else
      ##colorize source_version outgoing edges
      ${BIN}/sed -i -e 's/^\(\s\s'"${POSv}"'->.*\)\;$/\1 [color='"${EDG}"'\,style=bold];/g' ${PTH}/${chan}-${TRG}.gv

      ##capture indirect node edges
      EXT=($(grep "\s\s${POSv}->" ${PTH}/${chan}-${TRG}.gv | ${BIN}/cut -d">" -f2 | ${BIN}/cut -d";" -f1))

      ##save resulting channels for subsequent operations
      RES=("${RES[@]}" "${chan}")

      ##colorize EXT->LTS edges
      if [ "${chan}" = "fast" ]
        then
          POSc="" && POSc=`grep "\"${LTS[0]}\"" ${PTH}/${chan}-${TRG}.gv | awk {'print $1'}`
	  [[ "${POSc}" = "" ]] && continue
          for edge in ${EXT[@]}; do ${BIN}/sed -i -e 's/^\(\s\s'"${edge}"'->'"${POSc}"'.*\)\;$/\1 [color='"${EDG}"'\,style=dashed,label="Indirect"];/g' ${PTH}/${chan}-${TRG}.gv; done
	  ##put special color to direct LTS edge (if any)
	  ${BIN}/sed -i -e 's/^\(\s\s'"${POSv}"'->'"${POSc}"'\).*$/\1 [color='"${EDGt}"'\,style=bold,label="Direct"];/g' ${PTH}/${chan}-${TRG}.gv
      elif [ "${chan}" = "stable" ]
        then
          POSc="" && POSc=`grep "\"${LTS[1]}\"" ${PTH}/${chan}-${TRG}.gv | awk {'print $1'}`
          [[ "${POSc}" = "" ]] && continue
          for edge in ${EXT[@]}; do ${BIN}/sed -i -e 's/^\(\s\s'"${edge}"'->'"${POSc}"'.*\)\;$/\1 [color='"${EDG}"'\,style=dashed,label="Indirect"];/g' ${PTH}/${chan}-${TRG}.gv; done
          ##put special color to direct LTS edge (if any)
          ${BIN}/sed -i -e 's/^\(\s\s'"${POSv}"'->'"${POSc}"'.*\)\;$/\1 [color='"${EDGt}"'\,style=bold,label="Direct"];/g' ${PTH}/${chan}-${TRG}.gv
      fi
  fi
done

#abort if the provided release is not present within any of the channels
[[ ${#RES[@]} -eq 0 ]] && cout "ERROR" "Version '${VER}' not found within any of the ${TRG} channels. Aborting" && exit 1

#LABELING
for chan in ${RES[@]}; do ${BIN}/sed -i -e 's/TITLE/'"${chan}"'/g' ${PTH}/${chan}-${TRG}.gv; done
for chan in ${RES[@]}; do ${BIN}/sed -i -e 's/CHANNEL/"'"${chan}"'-'"${TRG}"' \('"$(${BIN}/date --rfc-3339=date)"'\)"/g' ${PTH}/${chan}-${TRG}.gv; done

#DRAW & EXPORT
for chan in ${RES[@]}; do ${BIN}/dot -Tsvg ${PTH}/${chan}-${TRG}.gv -o ${chan}-${TRG}_$(date +%Y%m%d).svg; [ $? -ne 0 ] && cout "ERROR" "Unable to export the results. Aborting" && exit 1 || cout "INFO" "Result exported as '${chan}-${TRG}_$(date +%Y%m%d).svg'"; done

#EOF
exit 0
