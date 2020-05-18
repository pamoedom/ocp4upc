#!/bin/sh
VERSION="1.7"
BIN="/usr/bin"

#INFO = (
#          author      => 'Pedro Amoedo'
#          contact     => 'pamoedom@redhat.com'
#          name        => 'ocp4upc.sh',
#          usage       => '(see below)',
#          description => 'OCP4 Upgrade Paths Checker',
#       );

#CHANGELOG = (
#              * v1.7
#                - Fixing non-default archs for 4.x mode
#                - Adding arch & mode (bw for 4.x) on exported files
#              * v1.6
#                - Colorize all possible 4.y targets (no more hardcoded limit)
#                - Reconfigure check_release to use parameters
#                - Adding exception catch when calling jq
#                - Tmp folder cleanup to avoid rare conditions with jq
#                - Fixed a bug with sed pattern when colorizing Direct edges
#                - Merged all variables in the same function
#              * v1.5
#                - Fixing multiple LTS points if stable!=fast (max 3)
#                - Include default minor version check if 4.x mode
#                - Adding JQ_SCRIPT parsing to allow multiple LTS
#                - Fixing default channels order (stable,fast), no longer relevant
#                - Indentation homogenization (no tabs)
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

#USAGE
usage(){
  ${BIN}/echo "---------------------------------------------------------"
  ${BIN}/echo "OCP4 Upgrade Paths Checker (stable & fast) v${VERSION}"
  ${BIN}/echo ""
  ${BIN}/echo "Usage:"
  ${BIN}/echo "$0 source_version [arch]"
  ${BIN}/echo ""
  ${BIN}/echo "Source Version:"
  ${BIN}/echo "4.x        Target same minor channels (B&W) (e.g. 4.2)"
  ${BIN}/echo "4.x.z      Target next minor channels (CLR) (e.g. 4.2.26)"
  ${BIN}/echo ""
  ${BIN}/echo "Arch:"
  ${BIN}/echo "amd64      x86_64 (default)"
  ${BIN}/echo "s390x      IBM System/390"
  ${BIN}/echo "ppc64le    POWER8 little endian"
  ${BIN}/echo "---------------------------------------------------------"
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

  ##URLs
  GPH='https://api.openshift.com/api/upgrades_info/v1/graph'
  REL='https://quay.io/api/v1/repository/openshift-release-dev/ocp-release'

  ##ARGs
  VER=${args[1]}
  [[ -z ${args[2]} ]] && ARC="amd64" || ARC=${args[2]}

  ##Misc
  PTH="/tmp/${cmd##*/}" #generate the tmp folder based on the current script name

  ##Target channel calculation
  MAJ=`${BIN}/echo ${VER} | ${BIN}/cut -d. -f1`
  MIN=`${BIN}/echo ${VER} | ${BIN}/cut -d. -f2`
  ERT=`${BIN}/echo ${VER} | ${BIN}/cut -d. -f3` #errata version provided?
  [[ "${ERT}" = "" ]] && TRG=${VER} || TRG="${MAJ}.`${BIN}/echo ${MIN}+1 | ${BIN}/bc`"

  ##Edge & Node colors
  EDG="blue" #source -> *
  EDGt="red" #source -> LTS
  ORG="salmon" #source
  DST="yellowgreen" #LTS
  DEF="lightgrey" #default

  ##Various Arrays
  CHA=(stable fast) #array of production-ready channels
  REQ=(curl jq dot bc) #array of pre-requisities
  RES=(stable fast) #array of resulting channels in case of discard, initiliazed here to allow 4.x mode
  LTS=() #array of latest target releases per channel.
  EXT=() #array of indirect nodes (if any)

  ##Ansi colors
  OK="${BIN}/echo -en \\033[1;32m" #green
  ERROR="${BIN}/echo -en \\033[1;31m" #red
  WARN="${BIN}/echo -en \\033[1;33m" #yellow
  INFO="${BIN}/echo -en \\033[1;34m" #blue
  NORM="${BIN}/echo -en \\033[0;39m" #default
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
      ${BIN}/rm ${PTH}/*.json ${PTH}/*.gv > /dev/null 2>&1
    else
      ${BIN}/mkdir ${PTH}; [ $? -ne 0 ] && cout "ERROR" "Unable to write in ${PTH}. Aborting" && exit 1
  fi
  cout "OK" ""
}

#RELEASE CHECKING
check_release(){
  if [ "${ERT}" = "" ]
    then
      cout "INFO" "Checking if '${VER}' (${ARC}) is a valid channel... " "-n"
      ${BIN}/curl -sH 'Accept:application/json' "${REL}" | ${BIN}/jq . > ${PTH}/ocp4-releases.json
      if [ "${ARC}" = "amd64" ]
        then
          ${BIN}/grep "\"${VER}.*-x86_64\"" ${PTH}/ocp4-releases.json &>/dev/null; [ $? -ne 0 ] && cout "ERROR" "" && exit 1
        else
          ${BIN}/grep "\"${VER}.*-${ARC}\"" ${PTH}/ocp4-releases.json &>/dev/null; [ $? -ne 0 ] && cout "ERROR" "" && exit 1
      fi
    else
      cout "INFO" "Checking if '${VER}' (${ARC}) is a valid release... " "-n"
      ${BIN}/curl -sH 'Accept:application/json' "${REL}" | ${BIN}/jq . > ${PTH}/ocp4-releases.json
      if [ "${ARC}" = "amd64" ]
        then
          ${BIN}/grep "\"${VER}-x86_64\"" ${PTH}/ocp4-releases.json &>/dev/null
          ##for amd64 make an extra attempt without -x86_64 because old releases don't have any suffix
          if [ $? -ne 0 ]
            then
              ${BIN}/grep "\"${VER}\"" ${PTH}/ocp4-releases.json &>/dev/null; [ $? -ne 0 ] && cout "ERROR" "" && exit 1
          fi
        else
          ${BIN}/grep "\"${VER}-${ARC}\"" ${PTH}/ocp4-releases.json &>/dev/null; [ $? -ne 0 ] && cout "ERROR" "" && exit 1
      fi
  fi
  cout "OK" ""
}

#OBTAIN UPGRADE PATHS JSONs
get_paths(){
  for chan in ${CHA[@]}; do ${BIN}/curl -sH 'Accept:application/json' "${GPH}?channel=${chan}-${TRG}&arch=${ARC}" > ${PTH}/${chan}-${TRG}.json; [ $? -ne 0 ] && cout "ERROR" "Unable to curl 'https://${GPH}?channel=${chan}-${TRG}&arch=${ARC}'. Aborting" && exit 1; done
}

#CAPTURE TARGETS ##TODO: do this against the API instead?
capture_lts(){
  LTS=("$(${BIN}/cat ${PTH}/fast-${TRG}.json | ${BIN}/jq . | ${BIN}/grep "\"${TRG}." | ${BIN}/cut -d'"' -f4 | ${BIN}/sort -urV)")
}

#JSON to GV
json2gv(){
  ##prepare the raw jq filter
  JQ_SCRIPT=$(${BIN}/echo '"digraph TITLE {\n  labelloc=t;\n  rankdir=BT;\n  label=CHANNEL" as $header |
    (
      [
        .nodes |
        to_entries[] |
        "  " + (.key | tostring) +
          " [ label=\"" + .value.version + "\"" + (
            if .value.metadata.url then ",url=\"" + .value.metadata.url + "\"" else "" end
	    ) + (')
  if [ "${ERT}" != "" ]
    then
      JQ_SCRIPT=${JQ_SCRIPT}$(${BIN}/echo '            if .value.version == "'"${VER}"'" then ",shape=polygon,sides=5,peripheries=3,style=filled,color='"${ORG}"'"')
    else
      JQ_SCRIPT=${JQ_SCRIPT}$(${BIN}/echo '            if .value.version == "" then ",shape=polygon,sides=5,peripheries=3,style=filled,color='"${ORG}"'"')
  fi
  JQ_SCRIPT=${JQ_SCRIPT}$(${BIN}/echo '            elif .value.version >= "'"${TRG}"'" then ",shape=square,style=filled,color=lightgrey"
            else ",shape=ellipse,style=filled,color='"${DEF}"'"
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
    [$header, $nodes, $edges, "}"] | join("\n")')

  ##generate the gv files
  for chan in ${CHA[@]}; do ${BIN}/jq -r "${JQ_SCRIPT}" ${PTH}/${chan}-${TRG}.json > ${PTH}/${chan}-${TRG}.gv; [ $? -ne 0 ] && cout "ERROR" "Unable to create ${PTH}/${chan}-${TRG}.gv file. Aborting" && exit 1; done
}

#DISCARD CHANNELS & COLORIZE EDGES ##TODO: move this logic into JQ_SCRIPT?
colorize(){
  RES=() #re-initialize the array in case of channel discarding (4.x.z mode)
  for chan in ${CHA[@]}
  do
    posV="" && posV=`grep "\"${VER}\"" ${PTH}/${chan}-${TRG}.gv | awk {'print $1'}`
    if [ "${posV}" = "" ]
      then
        cout "WARN" "Skipping channel '${chan}-${TRG}', version '${VER}' not found."
      else
        ##colorize source_version outgoing edges
        ${BIN}/sed -i -e 's/^\(\s\s'"${posV}"'->.*\)\;$/\1 [color='"${EDG}"'\,style=bold];/g' ${PTH}/${chan}-${TRG}.gv

        ##capture indirect node edges
        EXT=($(grep "\s\s${posV}->" ${PTH}/${chan}-${TRG}.gv | ${BIN}/cut -d">" -f2 | ${BIN}/cut -d";" -f1))

        ##save resulting channels for subsequent operations
        RES=("${RES[@]}" "${chan}")

        ##colorize EXT->LTS edges
        for target in ${LTS[@]}
        do
          posT="" && posT=`grep "\"${target}\"" ${PTH}/${chan}-${TRG}.gv | awk {'print $1'}`
          if [ "${posT}" != "" ]
            then
              for edge in ${EXT[@]}; do ${BIN}/grep "\s\s${edge}->${posT};" ${PTH}/${chan}-${TRG}.gv > /dev/null 2>&1; [ $? -eq 0 ] && ${BIN}/sed -i -e 's/^\(\s\s'"${edge}"'->'"${posT}"'.*\)\;$/\1 [color='"${EDG}"',style=dashed,label="Indirect"];/g' ${PTH}/${chan}-${TRG}.gv && ${BIN}/sed -i -e 's/^\(\s\s'"${posT}"'\s.*\),color=.*$/\1,color='"${DST}"' ]\;/g' ${PTH}/${chan}-${TRG}.gv; done
              ##put different color to Direct LTS edge (if any)
              ${BIN}/sed -i -e 's/^\(\s\s'"${posV}"'->'"${posT}"'\s\).*$/\1 [color='"${EDGt}"'\,style=bold,label="Direct"];/g' ${PTH}/${chan}-${TRG}.gv
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
drawing(){
  if [ "${ERT}" != "" ]
    then
      for chan in ${RES[@]}; do ${BIN}/dot -Tsvg ${PTH}/${chan}-${TRG}.gv -o ${chan}-${TRG}_${ARC}_$(date +%Y%m%d).svg; [ $? -ne 0 ] && cout "ERROR" "Unable to export the results. Aborting" && exit 1 || cout "INFO" "Result exported as '${chan}-${TRG}_${ARC}_$(date +%Y%m%d).svg'"; done
    else
      for chan in ${RES[@]}; do ${BIN}/dot -Tsvg ${PTH}/${chan}-${TRG}.gv -o ${chan}-${TRG}_${ARC}_bw_$(date +%Y%m%d).svg; [ $? -ne 0 ] && cout "ERROR" "Unable to export the results. Aborting" && exit 1 || cout "INFO" "Result exported as '${chan}-${TRG}_${ARC}_bw_$(date +%Y%m%d).svg'"; done
  fi
}

#SCRIPT WORKFLOW ($args[])
main(){
  args=("$@")
  declare_vars "$0" "${args[@]}"
  check_prereq
  [[ "${ERT}" != "" ]] && cout "INFO" "Errata provided (4.x.z mode), targeting '${TRG}' channels." || cout "INFO" "No errata provided (mode 4.x), targeting '${TRG}' channels."
  check_release
  get_paths
  [[ "${ERT}" != "" ]] && capture_lts
  json2gv
  [[ "${ERT}" != "" ]] && colorize
  labeling
  drawing
}

#STARTING POINT
[[ $# -lt 1 ]] && usage
main "$@"

#EOF
exit 0
