#!/bin/bash

declare -A MATRIX
declare -A PID_MATRIX
declare -A EXIT_CODES
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
INPUT=""
OUTPUT=""
OUTW=100
OUTH=100
HOR_TILES=9
VER_TILES=9
MAX_PROCESSES=4
CRF=30
LAST_RENDER=0
FFMPEG_PIDS=()
ALIVE_PIDS=()
DONE_PIDS=()

echo -en "\033[?25l"

usage() {
cat <<EOF
Usage: videocut [param] <arg>
  -i [file]	Input file path
  -o [dir] 	Output directory path
  -q [num]	CRF quality (default: 30)
  -t [num]	Square tile resolution (e.g. 200 will cut the file in 200x200 tiles)
  -w [num]	Output tile width (default: 100)
  -h [num]	Output tile height (default: 100)
  -x [num]	Number of horizontal tiles to cut (default: 10)
  -y [num]	Number of vertical tiles to cut (default: 10)
  -p [num]	Maximum number of ffmpeg processes (default: 4)  

EOF
echo -en "\033[?25h"
exit 0
}

cleanup() {
    local ALIVE_TO_KILL=()
    for PID in "${FFMPEG_PIDS[@]}"; do
        if kill -0 "$PID" 2>/dev/null; then
            ALIVE_TO_KILL+=("$PID")
        fi
    done

    if [ ${#ALIVE_TO_KILL[@]} -gt 0 ]; then
        kill "${ALIVE_TO_KILL[@]}" 2>/dev/null
    fi

    printf "\r\033[2K\033[91mUser interrupted\n\033[0m"
    echo -en "\033[?25h"
    exit 1
}

init_matrix() {
	for ((Y=0; Y<=VER_TILES; Y++)); do
		for ((X=0; X<=HOR_TILES; X++)); do
			MATRIX[$Y,$X]=37
		done
	done
}

render_matrix() {
	local VERTICAL=$((VER_TILES+2))
	for ((i=0; i<=VER_TILES; i++)); do
		for ((j=0; j<=HOR_TILES; j++)); do
			echo -en "\033[${MATRIX[$i,$j]}m■ \033[0m"
		done
		echo ""
	done
	printf "
${#DONE_PIDS[@]}/$(((HOR_TILES+1)*(VER_TILES+1)))"
	echo -en "\033[${VERTICAL}A\r"
}

update_matrix() {
	for ((i=0; i<=Y; i++)); do
		for ((j=0; j<=X; j++)); do
			if [[ ${FFMPEG_PIDS[@]} =~ ${PID_MATRIX[$i,$j]} ]]; then
				MATRIX[$i,$j]=34
			elif [[ ${DONE_PIDS[@]} =~ ${PID_MATRIX[$i,$j]} ]]; then
				MATRIX[$i,$j]=32
			fi
		done
	done
}

update_all_tiles() {
    for KEY in "${!PID_MATRIX[@]}"; do
        local pid=${PID_MATRIX[$KEY]}
        
        [[ ${MATRIX[$KEY]} -eq 32 || ${MATRIX[$KEY]} -eq 31 ]] && continue

        if ! kill -0 "$pid" 2>/dev/null; then
            wait "$pid"
            local exit_status=$?
            
            if [ $exit_status -eq 0 ]; then
                MATRIX[$KEY]=32
            else
                MATRIX[$KEY]=31
            fi
            DONE_PIDS+=( "$pid" )
        fi
    done
}

trap 'cleanup' SIGINT

if [ "$#" -eq 0 ]; then usage 
fi

while getopts ":i:o:q:t:w:h:x:y:p:" arg; do
  case $arg in
    i) 
      INPUT="$OPTARG"
      INPUT_FULLPATH="$(readlink -f $OPTARG)"
      INPUT_FILENAME="${OPTARG##*/}"
      INPUT_FILENAME_NOEXT="${INPUT_FILENAME%%.*}"
      ;;
    o) 
      if [[ $OPTARG != "" ]]; then 
        OUTPUT="${OPTARG}/${INPUT_FILENAME_NOEXT}"
        mkdir -p "$OUTPUT"
      fi
      ;;
    q) CRF=$OPTARG;;
    t) TILE=$OPTARG;;
    w) OUTW=$OPTARG;;
    h) OUTH=$OPTARG;;
    x) HOR_TILES=$((OPTARG - 1));;
    y) VER_TILES=$((OPTARG - 1));;
    p) MAX_PROCESSES=$OPTARG;;
    \?)
      printf "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      printf "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

if [[ $OUTPUT == "" ]]; then
  OUTPUT="${SCRIPT_DIR}/output/${INPUT_FILENAME_NOEXT}"
  mkdir -p $OUTPUT
fi

if [[ $INPUT == "" ]]; then
  printf "\033[2K\033[30;41mError:\033[0m Input file not specified\n"
  exit 1
fi

mkdir -p "${SCRIPT_DIR}/logs"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
export FFREPORT="file=${SCRIPT_DIR}/logs/ffmpeg_${TIMESTAMP}.log"

init_matrix
render_matrix
LAST_RENDER=$SECONDS
START_TIME=$SECONDS

for ((Y=0; Y<=$VER_TILES; Y++)); do
  for ((X=0; X<=$HOR_TILES; X++)); do

    ffmpeg -y -i "$INPUT" -an \
    -vf "crop=$TILE:$TILE:$X*$TILE:$Y*$TILE, scale=$OUTW:$OUTH" \
    -c:v libvpx-vp9 -pix_fmt yuva420p -auto-alt-ref 0 \
    -crf $CRF -v quiet -b:v 0 \
    "${OUTPUT}/tile_${Y}_${X}.webm" &
    
    CUR_PID=$!
    FFMPEG_PIDS+=( "$CUR_PID" )
    PID_MATRIX[$Y,$X]=$CUR_PID
    MATRIX[$Y,$X]=34

    while [ "$(( $(jobs -r | wc -l) ))" -ge "$MAX_PROCESSES" ]; do
        sleep 0.2
        update_all_tiles
        if (( SECONDS > LAST_RENDER )); then
            render_matrix
            LAST_RENDER=$SECONDS
        fi
    done

    update_all_tiles
    if (( SECONDS > LAST_RENDER )); then
        render_matrix
        LAST_RENDER=$SECONDS
    fi
  done
done

while [ $(jobs -r | wc -l) -gt 0 ]; do
    sleep 0.5
    update_all_tiles
    render_matrix
done

update_all_tiles
render_matrix

OFFSET=$((VER_TILES + 3))
echo -en "\033[${OFFSET}B\r"

START_TIME=${START_TIME:-0}
DURATION=$((SECONDS - START_TIME))
TOTAL_SIZE=$(du -sh "$OUTPUT" 2>/dev/null | cut -f1)
TOTAL_TILES=$(((HOR_TILES+1)*(VER_TILES+1)))

printf '\a\n'

echo -e "\n\e[30;42m DONE \e[0m"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "Time elapsed:  %02d:%02d:%02d\n" $((DURATION/3600)) $((DURATION%3600/60)) $((DURATION%60))
printf "Total tiles:   %s\n" "$TOTAL_TILES"
printf "Output size:   %s\n" "${TOTAL_SIZE:-0}"
printf "Directory:     %s\n" "$OUTPUT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo -en "\033[?25h"
