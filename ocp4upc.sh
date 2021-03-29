#!/usr/bin/env bash
set -o pipefail
[[ $(echo $BASH_VERSION | cut -d. -f1) -ge "5" ]] && set -o nounset #https://github.com/pamoedom/ocp4upc/issues/3

#GLOBAL STUFF
VERSION="3.2"
[[ "${OSTYPE}" == "linux-gnu"* ]] && BIN="/usr/bin/" || BIN="" #https://github.com/pamoedom/ocp4upc/issues/5
CHANDEF=(stable fast eus) #Default list of channels, add/remove channels only here (if needed), the script will do the rest ;) 

#INFO = (
#          author      => 'Pedro Amoedo'
#          contact     => 'pamoedom@redhat.com'
#          name        => 'ocp4upc.sh',
#          usage       => '(see function usage below)',
#          description => 'OCP4 Upgrade Paths Checker',
#          changelog   => '(see CHANGELOG file or git log)'
#       );

#ARGs DESCRIPTION
#$1=release/mode (mandatory), to be used as starting point + mode
#$2=architecture (optional), default is amd64

#EXIT CODES
#0 Successful run (EOF)
#1 Bad parameter (usage)
#2 Execution aborted (unexpected failure, network issue, etc)
#3 Execution interrupted (wrong input, timed out, etc)

#USAGE
function usage()
{
  ${BIN}echo "-----------------------------------------------------------------"
  ${BIN}echo "OCP4 Upgrade Paths Checker ($(${BIN}echo "${CHANDEF[@]}")) v${VERSION}"
  ${BIN}echo
  ${BIN}echo "Usage:"
  ${BIN}echo "$0 <release/mode> [arch]"
  ${BIN}echo
  ${BIN}echo "Release/Mode (mandatory):"
  ${BIN}echo "4.x        Extract default graphs using same-minor channels"
  ${BIN}echo "4.x.z      Generate upgrade paths using next-minor channels"
  ${BIN}echo "4.x.z.     Generate upgrade paths using same-minor channels"
  ${BIN}echo "4.x.z-4.y  Generate upgrade paths using multi-minor channels"
  ${BIN}echo
  ${BIN}echo "Arch (optional):"
  ${BIN}echo "amd64      x86_64 (default)"
  ${BIN}echo "s390x      IBM System/390"
  ${BIN}echo "ppc64le    POWER8/9 little endian"
  ${BIN}echo "-----------------------------------------------------------------"
  exit 1
}

#VARIABLES ($filename,$args[])
function declare_vars()
{
  local cmd="$1"
  local args=("$@")

  ##URLs
  GPH='https://api.openshift.com/api/upgrades_info/v1/graph'
  REL='https://quay.io/api/v1/repository/openshift-release-dev/ocp-release'

  ##ARGs
  [[ ${#args[1]} -lt 3 ]] && usage || VER=${args[1]}
  [[ -z ${args[2]-} ]] && ARC="amd64" || ARC=${args[2]}
  
  ##Target channel calculation & mode detection
  ! [[ ${VER} =~ ^[0-9]([.][0-9]+)([.][0-9]+|$).*$ ]] && usage
  MAJ=$(${BIN}echo ${VER} | ${BIN}cut -d. -f1)
  MIN=$(${BIN}echo ${VER} | ${BIN}cut -d. -f2)
  ERT=$(${BIN}echo ${VER} | ${BIN}cut -d. -f3-) #errata version provided?
  if [ ! -z ${ERT} ]; then
    [[ ${ERT} =~ ^[0-9]+$ ]] && TRG="${MAJ}.$(( ${MIN} + 1 ))" && MOD="4.x.z"
    [[ ${ERT} =~ ^[0-9]+[.]$ ]] && TRG="${MAJ}.${MIN}" && VER=$(${BIN}echo ${VER} | ${BIN}cut -d. -f1,2,3) && MOD="4.x.z." #https://github.com/pamoedom/ocp4upc/issues/4
    [[ ${ERT} =~ ^[0-9]+[-]+[0-9]+[.]+[0-9]$ ]] && TRG=$(${BIN}echo ${VER} | ${BIN}cut -d- -f2) && VER=$(${BIN}echo ${VER} | ${BIN}cut -d- -f1) && MOD="4.x.z-"
    [[ -z ${TRG-} ]] && usage #default in case of malformed source_version variable
  else
    VER=$(${BIN}echo ${VER} | ${BIN}cut -d. -f1,2)
    TRG="${VER}"
    MOD="4.x" #https://github.com/pamoedom/ocp4upc/pull/2
  fi
  if [ "${MOD}" == "4.x.z-" ]; then
    TRGa=() #array for multitarget mode
    TMPa=$((${MIN} + 1 )) #start target
    TMPb=$(${BIN}echo ${TRG} | ${BIN}cut -d. -f2) #end target
    while [ ${TMPa} -le ${TMPb} ]; do TRGa=("${TRGa[@]}" "${MAJ}.${TMPa}") && TMPa=$((${TMPa} + 1 )); done
  fi

  ##Edge & Node colors
  EDGs="blue" #source edges -> *
  EDGt="red" #source edges -> (LTS)
  NODs="salmon" #source node
  NODt="yellowgreen" #target nodes (LTS)
  NODi="lightgrey" #indirect nodes
  DEF="grey" #default color (keep it different)

  ##Various Arrays
  CHA=("${CHANDEF[@]}") #array of channels
  REQ=(curl jq dot) #array of pre-requisities
  RES=() #array of resulting channels in case of discard
  for chan in "${CHA[@]}"; do declare -a "LTS_${chan}=()"; done #arrays of possible target releases per channel.
  IND=() #array of indirect nodes (if any)
  EXT=() #array of direct nodes (if any)

  ##Ansi colors
  ERRO="${BIN}echo -en \\033[1;31m" #red
  SUCC="${BIN}echo -en \\033[1;32m" #green
  WARN="${BIN}echo -en \\033[1;33m" #yellow
  INFO="${BIN}echo -en \\033[1;34m" #blue
  DEBG="${BIN}echo -en \\033[1;35m" #purple
  INPT="${BIN}echo -en \\033[1;36m" #cyan
  HINT="${BIN}echo -en \\033[1;37m" #white
  NORM="${BIN}echo -en \\033[0;39m" #default

  ##Misc
  PTH="/tmp/${cmd##*/}_$(date +%Y%m%d)" #generate the tmp folder based on the current script name & date
  RELf="ocp4-releases.json"
  KEY='\n  Key \[rank=sink,shape=none,margin=0\.3,label=< <TABLE BORDER="1" STYLE="DOTTED" CELLBORDER="0" CELLSPACING="1" CELLPADDING="0"><TR><TD COLSPAN="2"><B>Key<\/B><\/TD><\/TR><TR><TD align="left">Direct Path<\/TD><TD><FONT COLOR="'"${EDGt}"'">\&\#10230\;<\/FONT><\/TD><\/TR><TR><TD align="left">Indirect Path<\/TD><TD><FONT COLOR="'"${EDGs}"'">\&\#8594\; \&\#10511\;<\/FONT><\/TD><\/TR><\/TABLE> >\];\n}' #embedded HTML legend
  KEYm='\n  Key \[rank=sink,shape=none,margin=0\.3,label=< <TABLE BORDER="1" STYLE="DOTTED" CELLBORDER="0" CELLSPACING="1" CELLPADDING="0"><TR><TD COLSPAN="2"><B>Key<\/B><\/TD><\/TR><TR><TD align="left">Direct Path<\/TD><TD><FONT COLOR="'"${EDGt}"'">\&\#10230\;<\/FONT><\/TD><\/TR><TR><TD align="left">Dead Path (if any)<\/TD><TD><FONT COLOR="'"${DEF}"'">\&\#10230\;<\/FONT><\/TD><\/TR><TR><TD align="left">Indirect Path<\/TD><TD><FONT COLOR="'"${EDGs}"'">\&\#8594\; \&\#10511\;<\/FONT><\/TD><\/TR><\/TABLE> >\];\n}' #embedded HTML legend (multigraph mode)
}

#PRETTY PRINT ($type_of_msg,$string,$echo_opts)
function cout()
{
  [[ -z ${2-} ]] && str="" || str=$2
  [[ -z ${3-} ]] && opts="" || opts=$3
  ${BIN}echo -n "[" && eval "\$$1" && ${BIN}echo -n "$1" && $NORM && ${BIN}echo -n "] " && ${BIN}echo ${opts} "$str"
}

#PREREQUISITES
function check_prereq()
{
  ##all tools available?
  cout "INFO" "Checking prerequisites ($(${BIN}echo "${REQ[@]}"))... " "-n"
  for tool in "${REQ[@]}"; do ${BIN}which ${tool} &>/dev/null; [ $? -ne 0 ] && cout "ERRO" "'${tool}' not present. Aborting execution." && exit 2; done

  ##tmp folder writable?
  if [ -d ${PTH} ]; then
    ${BIN}touch ${PTH}/test; [ $? -ne 0 ] && cout "ERRO" "Unable to write in '${PTH}'. Aborting execution." && exit 2
    ${BIN}rm ${PTH}/*.json ${PTH}/*.gv > /dev/null 2>&1
  else
    ${BIN}mkdir ${PTH}; [ $? -ne 0 ] && cout "ERRO" "Unable to write in '${PTH}'. Aborting execution." && exit 2
  fi
  cout "SUCC"
}

#RELEASE CHECKING
function check_release()
{
  ${BIN}curl -sH 'Accept:application/json' "${REL}" | ${BIN}jq . > ${PTH}/${RELf}
  if [ $? -ne 0 ]; then
    cout "WARN" "Unable to curl '${REL}'"
    cout "INPT" "Do you want to continue without sanity checks? (y/N):" "-n"
    read -t 10 yn
    [ $? -ne 0 ] && cout "ERRO" "Selection timed out. Execution interrupted." && exit 3
    [[ ${yn} =~ ^([yY][eE][sS]|[yY])$ ]] && return || cout "ERRO" "Invalid selection. Execution interrupted." && exit 3
  fi
  
  if [ "${MOD}" == "4.x" ]; then
    cout "INFO" "Checking if '${VER}' (${ARC}) has valid channels... " "-n"
    if [ "${ARC}" = "amd64" ]; then
      ${BIN}grep "\"${VER}.*-x86_64\"" ${PTH}/${RELf} &>/dev/null; [ $? -ne 0 ] && cout "ERRO" && exit 1
    else
      ${BIN}grep "\"${VER}.*-${ARC}\"" ${PTH}/${RELf} &>/dev/null; [ $? -ne 0 ] && cout "ERRO" && exit 1
    fi
  else
    cout "INFO" "Checking if '${VER}' (${ARC}) is a valid release... " "-n"
    if [ "${ARC}" = "amd64" ]; then
      ${BIN}grep "\"${VER}-x86_64\"" ${PTH}/${RELf} &>/dev/null;
      ##for amd64 make an extra attempt without -x86_64 because old releases don't have any suffix
      if [ $? -ne 0 ]; then
        ${BIN}grep "\"${VER}\"" ${PTH}/${RELf} &>/dev/null
	[ $? -ne 0 ] && cout "ERRO" && cout "HINT" "Run the script without parameters to see all the available options." && exit 1
      fi
    else
      ${BIN}grep "\"${VER}-${ARC}\"" ${PTH}/${RELf} &>/dev/null
      [ $? -ne 0 ] && cout "ERRO" && cout "HINT" "Run the script without parameters to see all the available options." && exit 1
    fi
  fi
  cout "SUCC"
}

#OBTAIN UPGRADE PATHS JSONs
function get_paths()
{
  local i=0
  [[ "${MOD}" == "4.x.z-" ]] && RES=() #re-initialize the array in case of multigraph mode

  for chan in "${CHA[@]}"; do
    ${BIN}curl -sH 'Accept:application/json' "${GPH}?channel=${chan}-${TRG}&arch=${ARC}" > ${PTH}/${chan}-${TRG}.json
    [[ $? -ne 0 ]] && cout "ERRO" "Unable to curl '${GPH}?channel=${chan}-${TRG}&arch=${ARC}'" && cout "ERRO" "Execution interrupted, try again later." && exit 3
    ##discard empty channels
    ${BIN}echo -n '{"nodes":[],"edges":[]}' | ${BIN}diff ${PTH}/${chan}-${TRG}.json - &>/dev/null
    [ $? -eq 0 ] && cout "WARN" "Skipping channel '${chan}-${TRG}_${ARC}', it's empty." && continue
    ##discard duplicated channels except for multigraph(4.x.z-) mode
    if [ $i -ne 0 ] && [ ${MOD} != "4.x.z-" ]; then
      ${BIN}diff ${PTH}/${chan}-${TRG}.json ${PTH}/${CHA[$(( $i - 1 ))]}-${TRG}.json &>/dev/null
      [ $? -eq 0 ] && cout "WARN" "Discarding channel '${chan}-${TRG}_${ARC}', it doesn't differ from '${CHA[$(( $i - 1 ))]}-${TRG}_${ARC}'." && continue
    fi
    RES=("${RES[@]}" "${chan}")
    (( i++ ))
  done
  ##reset channel list accordingly or abort if none available
  CHA=("${RES[@]}")
  if [ ${#CHA[@]} -eq 0 ]; then
    ##allow the user to make a 2nd run on the same minor channels if targeting a non-released version (corner case) https://github.com/pamoedom/ocp4upc/issues/4
    if [ "${MOD}" == "4.x.z" ] && [ "${TRG}" != "${MAJ}.${MIN}" ]; then
      cout "INPT" "You are targeting void '${TRG}' channels, do you want to re-target to '"${MAJ}.${MIN}"' (4.x.z. mode) instead? (y/N):" "-n"
      read -t 10 yn
      [[ ${yn} =~ ^([yY][eE][sS]|[yY])$ ]] && return 2
    fi
    cout "ERRO" "There are no channels to process. Aborting execution." && exit 2
  fi
}

#CAPTURE TARGETS ($max_targets) ##TODO: do this against the API instead?
function capture_lts()
{
  [[ -z ${1-} ]] && max="" || max=$1

  for chan in "${CHA[@]}"; do
    local var="LTS_${chan}"
    if [ -z ${max} ]; then
      eval "${var}"="("$(${BIN}cat ${PTH}/${chan}-${TRG}.json | ${BIN}jq . | ${BIN}sort -urV | ${BIN}grep "\"${TRG}." | ${BIN}cut -d'"' -f4 | ${BIN}xargs)")"
    else
      eval "${var}"="("$(${BIN}cat ${PTH}/${chan}-${TRG}.json | ${BIN}jq . | ${BIN}sort -urV | ${BIN}grep -m${max} "\"${TRG}." | ${BIN}cut -d'"' -f4 | ${BIN}xargs)")"
    fi
  done
}

#JSON to GV ($subgraph_num)
function json2gv()
{
  [[ -z ${1-} ]] && sub="0" || sub="$1"
  local mult="$(( ${sub} * 1000 ))" #multiplier to avoid node numbering overlapping between subgraphs

  ##prepare the raw jq filter
  if [ "${MOD}" == "4.x.z-" ]; then
    if [ "${sub}" == "1" ]; then
      JQ_SCRIPT=$(${BIN}echo '"digraph \"TITLE\" {\n  labelloc=c;\n  rankdir=BT;\n  label=\"MULTIGRAPH\";\n\n  subgraph cluster'"${sub}"' {\n  label=\"CHANNEL-'"${TRG}"'\"')
    else
      JQ_SCRIPT=$(${BIN}echo '"\n  subgraph cluster'"${sub}"' {\n  label=\"CHANNEL-'"${TRG}"'\"')
    fi
  else JQ_SCRIPT=$(${BIN}echo '"digraph \"TITLE\" {\n  labelloc=c;\n  rankdir=BT;\n  label=\"CHANNEL\";')
  fi
  JQ_SCRIPT=${JQ_SCRIPT}$(${BIN}echo '" as $header |
    (
      [
        .nodes |
        to_entries[] |
        "  " + (.key+'"${mult}"' | tostring) +
          " [ label=\"" + .value.version + "\"" + (
            if .value.metadata.url then ",url=\"" + .value.metadata.url + "\"" else "" end
            ) + (')
  if [ "${MOD}" != "4.x" ]; then
    JQ_SCRIPT=${JQ_SCRIPT}$(${BIN}echo '            if .value.version == "'"${VER}"'" then ",shape=polygon,sides=5,peripheries=2,style=filled,color='"${NODs}"'"')
  else
    JQ_SCRIPT=${JQ_SCRIPT}$(${BIN}echo '            if .value.version == "" then ",shape=polygon,sides=5,peripheries=3,style=filled,color='"${NODs}"'"')
  fi
  JQ_SCRIPT=${JQ_SCRIPT}$(${BIN}echo '            elif .value.version >= "'"${TRG}"'" then ",shape=square,style=filled,color='"${DEF}"'"
            else ",shape=ellipse,style=filled,color='"${DEF}"'"
            end
          ) +
          " ];"
      ] | join("\n")
    ) as $nodes |
    (
      [
        .edges[] |
        "  " + (.[0]+'"${mult}"' | tostring) + "->" + (.[1]+'"${mult}"' | tostring) + ";"
      ] | join("\n")
    ) as $edges |')
    if [ "${MOD}" == "4.x.z-" ]; then
      JQ_SCRIPT=${JQ_SCRIPT}$(${BIN}echo '            [$header, $nodes, $edges, "  }"] | join("\n")')
    else
      JQ_SCRIPT=${JQ_SCRIPT}$(${BIN}echo '            [$header, $nodes, $edges, "}"] | join("\n")')
    fi

  ##generate the gv files
  for chan in "${CHA[@]}"; do
    ${BIN}jq -r "${JQ_SCRIPT}" ${PTH}/${chan}-${TRG}.json > ${PTH}/${chan}-${TRG}_${VER}.gv
    [[ $? -ne 0 ]] && cout "ERRO" "Unable to create ${PTH}/${chan}-${TRG}_${VER}.gv file. Aborting execution." && exit 2
  done
}

#DISCARD CHANNELS & COLORIZE EDGES ##TODO: move this logic into JQ_SCRIPT?
function colorize()
{
  RESt=("${RES[@]}") #capture the previous contents for multigraph corner case (if needed)
  RES=() #re-initialize the array in case of channel discarding

  for chan in "${CHA[@]}"; do
    local var="LTS_${chan}"
    local ltsA=${var}[@]
    local posV=$(${BIN}grep "\"${VER}\"" ${PTH}/${chan}-${TRG}_${VER}.gv | awk {'print $1'})

    ##discarding channels/files depending on mode
    if [ "${MOD}" != "4.x.z-" ]; then
      [[ -z ${posV} ]] && cout "WARN" "Skipping channel '${chan}-${TRG}_${ARC}', version not found." && continue
      ${BIN}grep "\s\s${posV}->" ${PTH}/${chan}-${TRG}_${VER}.gv &>/dev/null #discard channel if VER doesn't have any outgoing edges
      [[ $? -ne 0 ]] && cout "WARN" "Skipping channel '${chan}-${TRG}_${ARC}', no upgrade paths available." && continue
      [[ -z ${!ltsA-} ]] && cout "WARN" "Skipping channel '${chan}-${TRG}_${ARC}', no upgrade paths available." && continue
    else
      [[ -z ${posV} ]] && cout "WARN" "Skipping file '${chan}-${TRG}_${VER}.gv', version not found." && continue
      ${BIN}grep "\s\s${posV}->" ${PTH}/${chan}-${TRG}_${VER}.gv &>/dev/null #discard channel if VER doesn't have any outgoing edges
      [[ $? -ne 0 ]] && cout "WARN" "Skipping file '${chan}-${TRG}_${VER}.gv', no upgrade paths available." && continue
      [[ -z ${!ltsA-} ]] && cout "WARN" "Skipping file '${chan}-${TRG}_${VER}.gv', no upgrade paths available." && continue
    fi

    ##capture list of outgoing edges (possible indirect nodes)
    IND=($(${BIN}grep "\s\s${posV}->" ${PTH}/${chan}-${TRG}_${VER}.gv | ${BIN}cut -d">" -f2 | ${BIN}cut -d";" -f1))

    ##colorize EXT->LTS edges
    for target in "${!ltsA}"; do
      posT=$(${BIN}grep "\"${target}\"" ${PTH}/${chan}-${TRG}_${VER}.gv | awk {'print $1'})
      if ! [ -z ${posT} ]; then
        for node in "${IND[@]}"; do
          ##Direct edges
          if [ "${node}" = "${posT}" ]; then
            ${BIN}sed -i -e 's/^\(\s\s'"${posV}"'->'"${posT}"'\)\;$/\1 \[color='"${EDGt}"'\,style=bold\];/' ${PTH}/${chan}-${TRG}_${VER}.gv
            ${BIN}sed -i -e 's/^\(\s\s'"${posT}"'\s.*\),color=.*$/\1,color='"${NODt}"' \]\;/' ${PTH}/${chan}-${TRG}_${VER}.gv
            continue
          fi
          ##Indirect edges
          ###grep is needed here because sed doesn't return a different exit code when matching
          ${BIN}grep "\s\s${node}->${posT};" ${PTH}/${chan}-${TRG}_${VER}.gv &>/dev/null
          if [ $? -eq 0 ]; then
            ##if match, colorize indirect node, indirect edge & target node
            ${BIN}sed -i -e 's/^\(\s\s'"${node}"'\s.*\),color=.*$/\1,color='"${NODi}"' \]\;/' ${PTH}/${chan}-${TRG}_${VER}.gv
            ${BIN}sed -i -e 's/^\(\s\s'"${node}"'->'"${posT}"'\)\;$/\1 \[color='"${EDGs}"',style=dashed\];/' ${PTH}/${chan}-${TRG}_${VER}.gv
            ${BIN}sed -i -e 's/^\(\s\s'"${posT}"'\s.*\),color=.*$/\1,color='"${NODt}"' \]\;/' ${PTH}/${chan}-${TRG}_${VER}.gv
            ##save final list of indirect nodes to be used below for pending source edges
            EXT=("${EXT[@]}" "${node}")
          fi
        done
      fi
    done

    ##colorize rest of source edges not yet processed
    for node in "${EXT[@]}"; do
      ${BIN}sed -i -e 's/^\(\s\s'"${posV}"'->'"${node}"'\)\;$/\1 \[color='"${EDGs}"',style=filled\];/' ${PTH}/${chan}-${TRG}_${VER}.gv
    done

    ##remove non involved nodes (with def color) + edges (without color) to simplify the graph
    ${BIN}sed -i -e '/color='"${DEF}"'/d;/[0-9]\;$/d' ${PTH}/${chan}-${TRG}_${VER}.gv

    ##include the graph legend except for multigraph mode (4.x.z-)
    [[ "${MOD}" != "4.x.z-" ]] && ${BIN}sed -i -e 's/^}$/'"${KEY}"'/' ${PTH}/${chan}-${TRG}_${VER}.gv

    ##save resulting channels for subsequent operations
    RES=("${RES[@]}" "${chan}")
  done

  ##abort if the provided release is not present within any of the channels
  if [ ${#RES[@]} -eq 0 ];then
    if [ "${MOD}" == "4.x.z-" ]; then
      RES=("${RESt[@]}") #grab the previous content in case of dead paths
      return 1
    else
      cout "ERRO" "Version '${VER}' not found (or not upgradable) within '${TRG}' channels. Aborting execution."
      cout "HINT" "Run the script without parameters to see other available modes."
      exit 2
    fi
  elif [ "${MOD}" == "4.x.z-" ]; then
    return 2
  fi
}

#LABELING
function label()
{
  local date="$(${BIN}date +%Y-%m-%d)"

  if [ "${MOD}" != "4.x.z-" ]; then
    for chan in "${RES[@]}"; do
      ${BIN}sed -i -e 's/TITLE/'"${chan}"'/;s/CHANNEL/'"${chan}"'-'"${TRG}"'_'"${ARC}"' \('"${date}"'\)/' ${PTH}/${chan}-${TRG}_${VER}.gv
    done
  else
    for chan in "${RES[@]}"; do
      ${BIN}sed -i -e 's/TITLE/'"${chan}"'-multigraph/;s/MULTIGRAPH/'"${chan}"'-multigraph_'"${ARC}"' \('"${date}"'\)/;s/CHANNEL/'"${chan}"'/' ${PTH}/${chan}-${TRG}_${VER}.gv
    done
  fi
}

#DRAW & EXPORT ($version_to_overwrite)
function draw()
{
  [[ -z ${1-} ]] && ver="${VER}" || ver=$1
  local date="$(${BIN}date +%Y%m%d)"

  [[ ${#RES[@]} -eq 0 ]] && cout "ERRO" "No channels to export, unexpected error. Aborting execution." && exit 2

  ##Mode selector
  case "${MOD}" in
  ###Default channels
  "4.x")
    for chan in "${RES[@]}"; do
      ${BIN}dot -Tsvg ${PTH}/${chan}-${TRG}_${ver}.gv -o ${chan}-${TRG}_${ARC}_${date}.svg
      if [ $? -ne 0 ]; then
        cout "ERRO" "Unable to export the results. Aborting execution."
        exit 2
      else
        cout "INFO" "Result exported as '${chan}-${TRG}_${ARC}_${date}.svg'"
      fi
    done
  ;;
  ###Single path modes
  "4.x.z" | "4.x.z.")
    for chan in "${RES[@]}"; do
      ${BIN}dot -Tsvg ${PTH}/${chan}-${TRG}_${ver}.gv -o ${chan}-${TRG}_${ver}_${ARC}_${date}.svg 
      if [ $? -ne 0 ]; then
        cout "ERRO" "Unable to export the results. Aborting execution."
        exit 2
      else
        cout "INFO" "Result exported as '${chan}-${TRG}_${ver}_${ARC}_${date}.svg'"
      fi
    done
  ;;
  ###Multigraph mode
  "4.x.z-")
    for chan in "${RES[@]}"; do
      ${BIN}dot -Tsvg ${PTH}/${chan}-multigraph.gv -o ${chan}-multigraph_${ver}-${TRG}_${ARC}_${date}.svg
      if [ $? -ne 0 ]; then
        cout "ERRO" "Unable to export the results. Aborting execution."
        exit 2
      else
        cout "INFO" "Result exported as '${chan}-multigraph_${ver}-${TRG}_${ARC}_${date}.svg'"
      fi
    done
  ;;
  *)
    usage
  ;;
  esac
}

#SCRIPT WORKFLOW ($args[])
function main()
{
  local args=("$@")
  declare_vars "$0" "${args[@]}"
  check_prereq
  check_release

  ##Mode selector
  case "${MOD}" in
  ###Default channels
  "4.x")
    cout "INFO" "Detected mode '${MOD}', extracting default '${TRG}' channels."
    get_paths
    json2gv
    label
    draw
  ;;
  ###Single path modes
  "4.x.z" | "4.x.z.")
    cout "INFO" "Detected mode '${MOD}', targeting channels '${TRG}' for upgrade path generation."
    get_paths
    #Allow a 2nd run if same minor upgrade path has been selected due to empty target channels (corner case)
    if [ $? -eq 2 ]; then
      CHA=("${CHANDEF[@]}")
      TRG="${MAJ}.${MIN}"
      MOD="4.x.z."
      cout "INFO" "Switched to mode '${MOD}', targeting channels '${TRG}' for upgrade path generation."
      get_paths
    fi
    capture_lts
    json2gv
    colorize
    label
    draw
  ;;
  ###Multigraph mode
  "4.x.z-")
    if [ "$(${BIN}echo ${TRG} | ${BIN}cut -d. -f1)" != "${MAJ}" ]; then
      cout "ERRO" "Multigraph mode can't target different major versions (${VER} !-> ${TRG}). Aborting execution."
      exit 2
    elif [ "$(${BIN}echo ${TRG} | ${BIN}cut -d. -f2)" -le "${MIN}" ]; then
      cout "ERRO" "Multigraph mode can only target higher minor versions. Aborting execution."
      exit 2
    fi

    cout "INFO" "Detected mode '${MOD}', targeting channels '$(${BIN}echo "${TRGa[@]}")' for multigraph generation."
    ##channel selection (default: first channel in the list)
    cout "INPT" "Select channel from [$(${BIN}echo "${CHANDEF[@]}")], press Enter for default value (${CHANDEF[0]}): " "-n"
    
    read -t 10 chan
    [ $? -ne 0 ] && cout "ERRO" "Selection timed out. Execution interrupted." && exit 3
    chan=${chan:-"${CHANDEF[0]}"}
    local match="false" #make the channel selection dynamic
    for opt in "${CHA[@]}"; do [[ "${opt}" != "${chan}" ]] && continue || match="true"; done
    [[ "${match}" != "true" ]] && cout "ERRO" "Invalid selection. Execution interrupted." && exit 3
    ##max depth selection (default: 2)
    cout "INPT" "Select max depth between [1-9], press Enter for default value (2): " "-n"
    read -t 10 max_depth
    max_depth=${max_depth:-"2"}
    [ $? -ne 0 ] && cout "ERRO" "Selection timed out. Execution interrupted." && exit 3
    ! [[ "${max_depth}" =~ ^[1-9]$ ]] && cout "ERRO" "Invalid selection. Execution interrupted." && exit 3
    local total=$((${#TRGa[@]} * ${max_depth}))
    [[ ${total} -gt 10 ]] && cout "WARN" "Targeting '${#TRGa[@]}' diff minor versions with '${max_depth}' releases per target (${total} edges), please be patient."

    ##execute initial target iteration
    CHA=("${chan}")
    local verI="${VER}" #save the initial version value for multigraph draw function
    TRG="${TRGa[0]}"
    cout "INFO" "Processing '${chan}-${TRG}' edges... "
    local i=1
    get_paths
    capture_lts "${max_depth}"
    json2gv "${i}"
    colorize
    if [ $? -eq 1 ]; then
      cout "ERRO" "Version '${VER}' not found (or not upgradable) within '${TRG}' channel. Aborting execution."
      cout "HINT" "Run the script without parameters to see other available modes."
      exit 2
    fi
    label
    ${BIN}cat ${PTH}/${chan}-${TRG}_${VER}.gv >> ${PTH}/${chan}-multigraph.gv #always dump the first target
    [ $? -ne 0 ] && cout "ERRO" "Unable to write in '${PTH}'. Aborting execution." && exit 2
    (( i++ ))

    local posVd=() #array of possible dead nodes (no upgradable to latest target)
    ##go through the next targets
    for target in "${TRGa[@]}"; do
      [[ ${TRG} == ${target} ]] && continue # skip first target from the list (already processed)
      local TRGp="${TRG}"
      TRG="${target}"
      cout "INFO" "Processing '${chan}-${TRG}' edges... "
      local var="LTS_${chan}"
      local ltsA=${var}[@] #save current LTS list
      local posVc=() #array of current LTS node positions within TRG
      local posVp=() #array of corresponding LTS node position within multigraph
      ##go through the captured releases per target
      for lts in "${!ltsA}"; do
        VER="${lts}"
        get_paths
        capture_lts "${max_depth}"
        json2gv "${i}"
        colorize
        if [ $? -eq 2 ]; then
          label
          ${BIN}cp -p ${PTH}/${chan}-${TRG}_${VER}.gv ${PTH}/${chan}-${TRG}_tmp.gv #overwrite and keep the latest run (more nodes)
          [ $? -ne 0 ] && cout "ERRO" "Unable to write in '${PTH}'. Aborting execution." && exit 2
          posVp=("${posVp[@]}" "$(${BIN}grep "\"${VER}\"" ${PTH}/${chan}-multigraph.gv | awk {'print $1'})")
        else
          posVd=("${posVd[@]}" "$(${BIN}grep "\"${VER}\"" ${PTH}/${chan}-multigraph.gv | awk {'print $1'})")
        fi
        (( i++ ))
      done
      if [ -f "${PTH}/${chan}-${TRG}_tmp.gv" ]; then
        posVc=($(${BIN}grep "\"${TRGp}.*\"" ${PTH}/${chan}-${TRG}_tmp.gv | awk {'print $1'}))
        for (( j=0; j<${#posVc[@]}; j++ )); do
          ##remove duplicated node(s) within tmp subgraph
          ${BIN}sed -i -e '/^\s\s'"${posVc[j]}"' \[/d' ${PTH}/${chan}-${TRG}_tmp.gv
          ##remove duplicated dead edges within tmp subgraph
          ${BIN}sed -i -e '/^\s\s.*->'"${posVc[j]}"'/d' ${PTH}/${chan}-${TRG}_tmp.gv
          ##homogenize edge colors with the other latest within tmp subgraph
          ${BIN}sed -i -e 's/^\(\s\s'"${posVc[j]}"'->[0-9]*\) \[color='"${EDGs}"'\,style=dashed\];$/\1 \[color='"${EDGt}"'\,style=bold\];/g' ${PTH}/${chan}-${TRG}_tmp.gv
          ##switch edge numbers to match with main multigraph file
          ${BIN}sed -i -e 's/^\s\s'"${posVc[j]}"'->/  '"${posVp[j]}"'->/g' ${PTH}/${chan}-${TRG}_tmp.gv
        done
        ${BIN}cat ${PTH}/${chan}-${TRG}_tmp.gv >> ${PTH}/${chan}-multigraph.gv #concatenate subgraph within multigraph
        [ $? -ne 0 ] && cout "ERRO" "Unable to write in '${PTH}'. Aborting execution." && exit 2
      else
        cout "ERRO" "No upgradable paths found for target '${TRG}'. Aborting execution." && exit 2
      fi
    done
  ${BIN}echo "}" >> ${PTH}/${chan}-multigraph.gv
  [ $? -ne 0 ] && cout "ERRO" "Unable to write in '${PTH}'. Aborting execution." && exit 2
  ##change color of dead paths (if any)
  for (( j=0; j<${#posVd[@]}; j++ )); do
    ${BIN}sed -i -e 's/^\(\s\s.*->'"${posVd[j]}"'\).*;$/\1 \[color='"${DEF}"'\,style=bold\];/g' ${PTH}/${chan}-multigraph.gv
  done
  ##insert legend (key)
  ${BIN}sed -i -e 's/^}$/'"${KEYm}"'/' ${PTH}/${chan}-multigraph.gv
  draw "${verI}"
  ;;
  *)
    usage
  ;;
  esac
}

#STARTING POINT
[[ $# -lt 1 ]] && usage
main "$@"

#EOF
exit 0
