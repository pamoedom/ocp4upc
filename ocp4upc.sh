#!/bin/sh
VERSION="1.4"
BIN="/usr/bin"

#INFO = (
#          author      => 'Pedro Amoedo'
#          contact     => 'pamoedom@redhat.com'
#          name        => 'ocp4upc.sh',
#          usage       => '(see below)',
#          description => 'OCP4 Upgrade Paths Checker',
#       );

#CHANGELOG = (
#              * v1.4
#                - Modularization everywhere
#                - Default channel reports if no errata provided
#                - Fixed multiple LTS direct edges when stable!=fast
#                - Added ARC into the graph title
#                - Improved the usage help
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

#ARGs DESCRIPTION
#$1=source_release to be used as starting point
#$2=architecture (optional), default is amd64

#ANSI COLORS
ansi_colors(){
  OK="${BIN}/echo -en \\033[1;32m"
  ERROR="${BIN}/echo -en \\033[1;31m"
  WARN="${BIN}/echo -en \\033[1;33m"
  INFO="${BIN}/echo -en \\033[1;34m"
  NORM="${BIN}/echo -en \\033[0;39m"
}

#USAGE
usage(){
  ${BIN}/echo "---------------------------------------------"
  ${BIN}/echo "OCP4 Upgrade Paths Checker (fast,stable) v${VERSION}"
  ${BIN}/echo ""
  ${BIN}/echo "Usage:"
  ${BIN}/echo "$0 source_version [arch]"
  ${BIN}/echo ""
  ${BIN}/echo "Source Version:"
  ${BIN}/echo "4.x        Generate 4.x channels with default paths"
  ${BIN}/echo "4.x.z      Generate 4.y channels with colorized paths"
  ${BIN}/echo ""
  ${BIN}/echo "Arch:"
  ${BIN}/echo "amd64      x86_64 (default)"
  ${BIN}/echo "s390x      IBM System/390"
  ${BIN}/echo "ppc64le    POWER8 little endian"
  ${BIN}/echo "---------------------------------------------"
  exit 1
}

#PRETTY PRINT ($type_of_msg,$string,$echo_opts)
cout(){
  ${BIN}/echo -n "[" && eval "\$$1" && ${BIN}/echo -n "$1" && $NORM && ${BIN}/echo -n "] " && ${BIN}/echo $3 "$2"
}

#VARIABLES ($filename,$args[])
declare_vars(){
  cmd="$1"
  args=("$@")
  GPH='https://api.openshift.com/api/upgrades_info/v1/graph'
  REL='https://quay.io/api/v1/repository/openshift-release-dev/ocp-release'
  VER=${args[1]}
  MAJ=`${BIN}/echo ${VER} | ${BIN}/cut -d. -f1`
  MIN=`${BIN}/echo ${VER} | ${BIN}/cut -d. -f2`
  ERT=`${BIN}/echo ${VER} | ${BIN}/cut -d. -f3` #errata version provided?
  [[ "${ERT}" = "" ]] && TRG=${VER} || TRG="${MAJ}.`${BIN}/echo ${MIN}+1 | ${BIN}/bc`"
  EDG="blue"
  EDGt="red"
  ORG="salmon"
  DST="yellowgreen"
  [[ -z ${args[2]} ]] && ARC="amd64" || ARC=${args[2]}
  POSv=""
  POSc=""
  PTH="/tmp/${cmd##*/}" #generate the tmp folder based on the current script name
  CHA=(fast stable) #the order here is relevant to colorize the LTS per channel, see JQ_SCRIPT below.
  REQ=(curl jq dot bc)
  RES=(fast stable) #array of resulting channels in case of discard, initiliazed to allow TRG=VER
  LTS=() #array of latest target releases per channel.
  EXT=() #array of indirect nodes (if any)
}

#PREREQUISITES
check_prereq(){
  ##all tools available?
  cout "INFO" "Checking prerequisites... " "-n"
  for tool in ${REQ[@]}; do ${BIN}/which $tool &>/dev/null; [ $? -ne 0 ] && cout "ERROR" "'$tool' not present. Aborting" && exit 1; done

  ##tmp folder writable?
  if [ -d ${PTH} ]
    then
      ${BIN}/touch ${PTH}/test; [ $? -ne 0 ] && cout "ERROR" "Unable to write in ${PTH}. Aborting" && exit 1
    else
      ${BIN}/mkdir ${PTH}; [ $? -ne 0 ] && cout "ERROR" "Unable to write in ${PTH}. Aborting" && exit 1
  fi
  cout "OK" ""
}

#RELEASE CHECKING
check_release(){
  cout "INFO" "Checking if '${VER}' (${ARC}) is a valid release... " "-n"
  ${BIN}/curl -sH 'Accept:application/json' "${REL}" | ${BIN}/jq . > ${PTH}/ocp4-releases.json
  if [ "${ARC}" = "amd64" ]
    then
      ${BIN}/grep "\"${VER}-x86_64\"" ${PTH}/ocp4-releases.json &>/dev/null
    ##for amd64 make an extra attempt without -x86_64 because old releases do not contain that suffix
    if [ $? -ne 0 ]
      then
        ${BIN}/grep "\"${VER}\"" ${PTH}/ocp4-releases.json &>/dev/null; [ $? -ne 0 ] && cout "ERROR" "" && exit 1
    fi
  else
    ${BIN}/grep "\"${VER}-${ARC}\"" ${PTH}/ocp4-releases.json &>/dev/null; [ $? -ne 0 ] && cout "ERROR" "" && exit 1
  fi
  cout "OK" ""
}

#OBTAIN UPGRADE PATHS JSONs
upgrade_paths(){
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
}

#DISCARD CHANNELS & COLORIZE EDGES (TODO: move this logic into JQ_SCRIPT?)
colorize(){
  RES=() #remove the array in case of discarding
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
        for target in ${LTS[@]}
        do
          POSc="" && POSc=`grep "\"${target}\"" ${PTH}/${chan}-${TRG}.gv | awk {'print $1'}`
	  if [ "${POSc}" != "" ]
            then
              for edge in ${EXT[@]}; do ${BIN}/sed -i -e 's/^\(\s\s'"${edge}"'->'"${POSc}"'.*\)\;$/\1 [color='"${EDG}"'\,style=dashed,label="Indirect"];/g' ${PTH}/${chan}-${TRG}.gv; done
              ##put different color to direct LTS edge (if any)
              ${BIN}/sed -i -e 's/^\(\s\s'"${POSv}"'->'"${POSc}"'\).*$/\1 [color='"${EDGt}"'\,style=bold,label="Direct"];/g' ${PTH}/${chan}-${TRG}.gv
          fi
        done
    fi
  done

  ##abort if the provided release is not present within any of the channels
  [[ ${#RES[@]} -eq 0 ]] && cout "ERROR" "Version '${VER}' not found within any of the ${TRG} channels. Aborting" && exit 1
}

#LABELING
labeling(){
  for chan in ${RES[@]}; do ${BIN}/sed -i -e 's/TITLE/'"${chan}"'/g' ${PTH}/${chan}-${TRG}.gv; done
  for chan in ${RES[@]}; do ${BIN}/sed -i -e 's/CHANNEL/"'"${chan}"'-'"${TRG}"' \('"$(${BIN}/date --rfc-3339=date)"'\) ['"${ARC}"']"/g' ${PTH}/${chan}-${TRG}.gv; done
}

#DRAW & EXPORT
draw(){
  for chan in ${RES[@]}; do ${BIN}/dot -Tsvg ${PTH}/${chan}-${TRG}.gv -o ${chan}-${TRG}_$(date +%Y%m%d).svg; [ $? -ne 0 ] && cout "ERROR" "Unable to export the results. Aborting" && exit 1 || cout "INFO" "Result exported as '${chan}-${TRG}_$(date +%Y%m%d).svg'"; done
}

#SCRIPT WORKFLOW ($args[])
main(){
  args=("$@")
  ansi_colors
  declare_vars "$0" "${args[@]}"
  check_prereq
  [[ "${ERT}" != "" ]] && check_release || cout "WARN" "No errata version detected, generating default ${VER} (${ARC}) channels..."
  upgrade_paths
  [[ "${ERT}" != "" ]] && colorize
  labeling
  draw
}

#MAIN CALL
[[ $# -lt 1 ]] && usage
main "$@"

#EOF
exit 0
