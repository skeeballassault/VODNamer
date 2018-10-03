if (( ${BASH_VERSINFO[0]} < 4 )); then
	echo "This script requires Bash version >= 4.";
	exit 1;
fi

# Get directory of script itself
CURR_DIR="$(cd "$(dirname $0)" && pwd)"

# Declare contants for color highlighting
# Remember to use -e with echo if using these codes
RED='\033[0;31m'
L_RED='\033[1;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
L_BLUE='\033[1;34m'
NC='\033[0m' # No Color, goes after each opening tag


echo -e "${GREEN}VODNamer (launch with "-h" to see options)${NC}"


# Declare option arrays for singles characters/colors and doubles colors
characters=(
	"Bowser"
	"Captain Falcon"
	"Donkey Kong"
	"Dr. Mario"
	"Falco"
	"Fox"
	"Ganondorf"
	"Ice Climbers"
	"Jigglypuff"
	"Kirby"
	"Link"
	"Luigi"
	"Mario"
	"Marth"
	"Mewtwo"
	"Mr. Game & Watch"
	"Ness"
	"Peach"
	"Pichu"
	"Pikachu"
	"Roy"
	"Samus"
	"Sheik"
	"Yoshi"
	"Young Link"
	"Zelda"
)

character_colors=(
	"Neutral Red Blue Black" # Bowser
	"Neutral Black Red White Green Blue" # Captain Falcon
	"Neutral Black Red Blue Green" # Donkey Kong
	"White Red Blue Green Black" # Dr. Mario
	"Neutral Red Blue Green" # Falco
	"Neutral Red Blue Green" # Fox
	"Neutral Red Blue Green Purple" # Ganondorf
	"Neutral Green Orange Red" # Ice Climbers
	"Naked Flower Bow Headband Crown" # Jigglypuff
	"Neutral Yellow Blue Red Green White" # Kirby
	"Green Red Blue Black White" # Link
	"Green White Blue Pink" # Luigi
	"Red Yellow Black Blue Green" # Mario
	"Blue Red Green Black White" # Marth
	"Neutral Red Blue Green" # Mewtwo
	"Black Red Blue Green" # Mr. Game and Watch
	"Neutral Yellow Blue Green" # Ness
	"Pink Daisy White Blue Green" # Peach
	"Naked Scarf Goggles Backpack" # Pichu
	"Naked Ballcap Wizard Fedora" # Pikachu
	"Neutral Red Blue Green Yellow" # Roy
	"Neutral Pink Brown Green Purple" # Samus
	"Neutral Red Blue Green White" # Sheik
	"Green Red Blue Yellow Pink Cyan" # Yoshi
	"Green Red Blue White Black" # Young Link
	"Neutral Red Blue Green White" # Zelda
)

# Declare if script is being run in debug mode, uncomment the DEBUG variable to enable debug mode (outputs echos for many important variables)
debug () {
	if [ -n "${DEBUG_MODE+1}" ]; then
		echo -e "${L_RED}${1}${NC}"
	fi
}

args_folder=""
args_link=""

while getopts "f:l:dxrh" opt; do
	case ${opt} in
		f )
			args_folder=$OPTARG
		;;
		l )
			args_link=$OPTARG
		;;
		d )
			DEBUG_MODE=yes
		;;
		x )
			PREVIEW_DISABLE=yes
		;;
		r )
			FORCE_REGEN=yes
		;;
		h )
			echo "Available arguments:"
			echo "-f	Folder to scan for video files (input required)"
			echo "-l	Link to tournament, can be any link from a Smash.gg tournament page (input required)"
			echo "-d	Debug mode switch, outputs many behind the scenes variables"
			echo "-x	Manually disable preview mode"
			echo "-r	Force regeneration of previews, even if they already exist"
			echo "-h	Displays this dialog, then exits"
			exit 1
		;;
	esac
done

debug "DEBUG MODE ACTIVE"

# Yell at user about dependencies (function)
dep_check () {
	deps_met=0 # 0 = true, 1 = false
	for program in "$@"; do
		if command -v $program >/dev/null 2>&1; then
			echo -e "$program: ${GREEN}YES${NC}"
		else
			echo -e "$program: ${ORANGE}NO${NC}"
			deps_met=1
		fi
	done
	return $deps_met
}

# Platform detection between Mac/Linux
platform='unknown'
unamestr=$(uname)
jq=''
if [[ "$unamestr" == 'Linux' ]]; then
	platform='Linux'
	jq="$CURR_DIR/jq/jq-linux64"
	# Dependencies for Linux
	if dep_check ffmpeg feh bc; then
		preview_mode=true
	fi
elif [[ "$unamestr" == 'FreeBSD' || "$unamestr" == 'Darwin' ]]; then
	platform='Mac OS X/FreeBSD'
	jq="$CURR_DIR/jq/jq-osx-amd64"
	# Dependencies for Mac
	if dep_check ffmpeg bc; then
		preview_mode=true
	fi
fi

if [ ! -f "${CURR_DIR}/OpenSans-Regular.ttf" ]; then
	echo -e "${ORANGE}Included font file not found!${NC}"
	preview_mode=false
fi

if [ -n "${PREVIEW_DISABLE+1}" ]; then
	preview_mode=false
fi

if [ "$preview_mode" = true ]; then
	echo -e "${GREEN}Preview mode is enabled!${NC}"
else
	echo -e "${ORANGE}Preview mode is disabled!${NC}"
fi

# Construct correct link for Smash.gg API

#api_input_link="https://smash.gg/tournament/s-ps-weekly-60/events/melee-singles/standings"
#api_input_link="https://smash.gg/tournament/sv7-prelude/events/melee-singles/standings"

while true; do
	if [[ -z $args_link ]]; then
		read -p "Please give a link to the appropriate tournament: " api_input_link
	else
		api_input_link=$args_link
	fi
	if curl --output /dev/null --silent --head --fail "$api_input_link" && [[ "$api_input_link" == *"smash.gg/tournament"* ]]; then
		break
	else
		echo -e "${ORANGE}Invalid tournament link!${NC}"
		args_link=""
	fi
done

api_tournament_slug="$(echo "$api_input_link" | cut -d/ -f5)"
api_tournament_base_link='https://api.smash.gg/tournament/'
api_tournament_variables='?expand[]=event&expand[]=phase&expand[]=groups'
api_tournament_link="$api_tournament_base_link$api_tournament_slug$api_tournament_variables"

debug "$api_tournament_link"

# Make initial API calls to get tournament name/events available
JSON_tourney=$(curl -gs $api_tournament_link)

# Get tournament title
title_tournament=$(echo $JSON_tourney | $jq '.entities.tournament.name')

# Strips quotes surrounding title name
title_tournament=$(sed -e 's/^"//' -e 's/"$//' <<<"$title_tournament")

echo -e "${GREEN}$title_tournament${NC}"

# Declare the arrays that hold each event's name and ID from the tournament being scanned
event_name=()
event_id=()

# This loop filters in the JSON data into the two arrays
while IFS=$'\t' read -r name id; do
	event_name+=("$name")
	event_id+=("$id")
done <<< "$(echo $JSON_tourney | $jq -r '.entities.event[] | [.name, .id] | @tsv')"

chosen_event_id=''
title_event=''

PS3='Choose the appropriate event (type "q" to quit the script): '
select opt in "${event_name[@]}"; do
	if [[ $REPLY =~ ^-?[0-9]+$ && $REPLY -le ${#event_name[@]} && $REPLY > 0 ]]; then
		event_index=$(($REPLY - 1))
		chosen_event_id="${event_id[$event_index]}"
		title_event=$opt
		break
	elif [[ "$REPLY" == "q" ]]; then
		exit 1
	else
		echo -e "${ORANGE}Selection is invalid!${NC}"
	fi
done

echo -e "${GREEN}$title_event${NC}"

# Declare the array that holds each phase's ID

chosen_phase_ids=()
declare -A chosen_phase_names

# This loop filters the correct phase IDs into the new array based on their event ID

while IFS=$'\t' read -r id eventId name; do
	if [ "$eventId" == "$chosen_event_id" ]; then
		chosen_phase_ids+=("$id")
		chosen_phase_names[$id]="$name"
	fi
done <<< "$(echo $JSON_tourney | $jq -r '.entities.phase[] | [.id, .eventId, .name] | @tsv')"

debug "${chosen_phase_ids[*]}"
debug "${chosen_phase_names[*]}"

# Declare the array that holds each phase's ID

chosen_phase_group_ids=()
declare -A chosen_phase_group_phase_names

# This loop filters the correct phase group IDs into the new array based on their phase ID

while IFS=$'\t' read -r id phaseId; do
	for i in "${chosen_phase_ids[@]}"; do
		if [ "$i" == "$phaseId" ]; then
			chosen_phase_group_ids+=("$id")
			chosen_phase_group_phase_names[$id]="${chosen_phase_names[$phaseId]}"
		fi
	done
done <<< "$(echo $JSON_tourney | $jq -r '.entities.groups[] | [.id, .phaseId] | @tsv')"

debug "${chosen_phase_group_ids[*]}"
debug "${chosen_phase_group_phase_names[*]}"

# Declare new parts for construction of API links for each phase group

api_phase_group_base_link='https://api.smash.gg/phase_group/'
api_phase_group_variables='?expand[]=sets&expand[]=entrants'
phase_group_api_links=()

# Loop through the collected phase group IDs to construct API links for each

for i in "${chosen_phase_group_ids[@]}"; do
	new_link="$api_phase_group_base_link$i$api_phase_group_variables"
	phase_group_api_links+=("$new_link")
done

debug "${phase_group_api_links[*]}"

# Download the JSON from each new API link

JSON_phase_groups=()

for i in "${phase_group_api_links[@]}"; do
	JSON_temp=$(curl -gs $i)
	JSON_phase_groups+=("$JSON_temp")
done

# Declare variables to hold data about entrants and sets

declare -A entrants
declare -A entrants_lc_name2id

set_id=()
set_player1=()
set_player2=()
set_round=()

# Declare variables for winner's, losers, and pools sets, in order to have them all in order
pools_id=()
pools_player1=()
pools_player2=()
pools_round=()

winners_id=()
winners_player1=()
winners_player2=()
winners_round=()

losers_id=()
losers_player1=()
losers_player2=()
losers_round=()

# Declare variables to hold details of grands (to put grands at bottom of set list instead of being sandwiched between winners and losers, and also to remove second set of grands)
grands_id=""
grands_player1=""
grands_player2=""
grands_round=""

# Recieve entrants and sets from each collected JSON

tab=$(printf '\t')
doubles=false
for i in "${JSON_phase_groups[@]}"; do

	# Read out entrants to array for their ID and tag
	while IFS=$'\t' read -r id gamerTag; do
		if [[ $gamerTag = *${tab}* ]]; then
			doubles=true
			gamerTag=${gamerTag//${tab}/ + }
		fi
		entrants["$id"]=$gamerTag
		entrants_lc_name2id["$(echo $gamerTag | awk '{print tolower($0)}')"]=$id
	done <<< "$(echo $i | $jq -r '.entities.entrants[] | [.id, .mutations.participants[].gamerTag] | @tsv')"

	while IFS=$'\t' read -r id phaseGroupId entrant1PrereqType entrant2PrereqType entrant1Id entrant2Id midRoundText; do
		if [ -n "$entrant1Id" ] && [ -n "$entrant2Id" ] && [ "$entrant1PrereqType" != "bye" ] && [ "$entrant2PrereqType" != "bye" ]; then # the first two checks clear sets with null entrant values (needed for non-existent Grands 2 sets) and the second two checks are for if the set was a bye
			if [[ "$midRoundText" == Round\ [0-9]* ]]; then

				midRoundText="${chosen_phase_group_phase_names[$phaseGroupId]} $midRoundText"

				pools_id+=("$id")
				pools_player1+=("$entrant1Id")
				pools_player2+=("$entrant2Id")
				pools_round+=("$midRoundText")

			elif [[ "$midRoundText" == Winners* ]]; then

				if [[ "$midRoundText" == Winners\ [0-9]* ]]; then
					round_type=${midRoundText%% *}
					round_number=${midRoundText##* }
					midRoundText="$round_type Round $round_number"
				fi

				winners_id+=("$id")
				winners_player1+=("$entrant1Id")
				winners_player2+=("$entrant2Id")
				winners_round+=("$midRoundText")

			elif [[ "$midRoundText" == Losers* ]]; then

				if [[ "$midRoundText" == Losers\ [0-9]* ]]; then
					round_type=${midRoundText%% *}
					round_number=${midRoundText##* }
					midRoundText="$round_type Round $round_number"
				fi

				losers_id+=("$id")
				losers_player1+=("$entrant1Id")
				losers_player2+=("$entrant2Id")
				losers_round+=("$midRoundText")

			elif [[ "$midRoundText" == "Grand Final" ]]; then

				grands_id="$id"
				grands_player1="$entrant1Id"
				grands_player2="$entrant2Id"
				grands_round="$midRoundText"

			fi

			debug "$id $title_tournament $title_event - ${entrants[$entrant1Id]} vs ${entrants[$entrant2Id]} - $midRoundText"
		fi
	done <<< "$(echo $i | $jq -r '.entities.sets[] | [.id, .phaseGroupId, .entrant1PrereqType, .entrant2PrereqType, .entrant1Id, .entrant2Id, .midRoundText] | @tsv')"

done

if [ ${#pools_id[@]} -ne 0 ]; then
	for i in $(seq 0 $((${#pools_id[@]} - 1))); do
		set_id+=("${pools_id[$i]}")
		set_player1+=("${pools_player1[$i]}")
		set_player2+=("${pools_player2[$i]}")
		set_round+=("${pools_round[$i]}")
	done
fi

for i in $(seq 0 $((${#winners_id[@]} - 1))); do
	set_id+=("${winners_id[$i]}")
	set_player1+=("${winners_player1[$i]}")
	set_player2+=("${winners_player2[$i]}")
	set_round+=("${winners_round[$i]}")
done

for i in $(seq 0 $((${#losers_id[@]} - 1))); do
	set_id+=("${losers_id[$i]}")
	set_player1+=("${losers_player1[$i]}")
	set_player2+=("${losers_player2[$i]}")
	set_round+=("${losers_round[$i]}")
done

set_id+=("$grands_id")
set_player1+=("$grands_player1")
set_player2+=("$grands_player2")
set_round+=("$grands_round")

while true; do
	if [[ -z $args_folder ]]; then
		read -e -p "Please give a folder containing the appropriate videos: " video_folder
	else
		video_folder=$args_folder
	fi
	if [[ -d $video_folder ]]; then
		echo -e "${GREEN}Reading videos from $video_folder...${NC}"
		break
	else
		echo -e "${ORANGE}Invalid folder choice!${NC}"
		args_folder=""
	fi
done

shopt -s extglob nullglob

# TODO - Setting IFS allows for filenames with spaces, but breaks multiple character input

IFS=$'\n'
for video in $video_folder/*.@(mp4|mov|flv|mkv); do

	unset IFS

	debug "$video"

	filename=$(basename "$video")
	extension="${filename##*.}"
	basename="${filename%.*}"

	# Preview mode - FFMpeg pulls a few random frames from the video at hand and shows them to the script runner to allow easy viewing of which players are present

	if [ "$preview_mode" = true ]; then
		mkdir -p "$video_folder/previews"
		if [[ ! -f "$video_folder/previews/PREVIEW-$basename.png" || -v FORCE_REGEN ]]; then
			if [[ -v FORCE_REGEN ]]; then
				echo -e "${L_BLUE}Force regenerating${GREEN} preview for ${basename}...${NC}"
			else
				echo -e "${GREEN}Generating preview for ${basename}...${NC}"
			fi

			duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$video")

			video_length_1percent=$(bc <<< "scale = 3;$duration / 100")

			designated_points=(10 20 30 40 50 60 70 80 90)
			video_timestamps=()

			for i in "${designated_points[@]}"; do
				video_timestamps+=( $(bc <<< "scale = 3;$video_length_1percent * $i") )
			done

			temp_dir=$(mktemp -d)

			counter=0
			for i in "${video_timestamps[@]}"; do
				ffmpeg -hide_banner -loglevel panic -y -ss "$i" -i "$video" -vframes 1 -vf drawtext="fontfile=${CURR_DIR}/OpenSans-Regular.ttf: text='$(($counter + 1))': fontcolor=white: fontsize=100: box=1: boxcolor=black@0.5: boxborderw=5: x=(w-text_w)/2: y=(h-text_h)/2" "$temp_dir/$basename-${designated_points[$counter]}.png"
				(( counter++ ))
			done

			ffmpeg -hide_banner -loglevel panic -y -pattern_type glob -i "$temp_dir/*.png" -filter_complex scale=512:288,tile=3x3:margin=2:padding=5 "$video_folder/previews/PREVIEW-$basename.png"

			rm -R ${temp_dir}
		else
			echo -e "${L_BLUE}Preview already generated for this file...${NC}"
		fi
	fi

	# Accept input for one player's name, then give selector for every set they played to choose the appropriate set

	if [[ $preview_mode == true ]]; then
		case $platform in
			"Linux")
				feh -g 1024x768 "$video_folder/previews/PREVIEW-$basename.png" &
				preview_pid=$!
				;;
			"Mac OS X/FreeBSD")
				# TODO - make preview appear smaller/less in the way
				qlmanage -p "$video_folder/previews/PREVIEW-$basename.png" >& /dev/null &
				preview_pid=$!
				;;
			esac
	fi

	while true; do
		read -p "Enter one player name from $basename: " search_input
		search_input=$(echo $search_input | awk '{print tolower($0)}')
		search_match=""
		# Loop reads search input and checks all tags (split apart if doubles)
		if [ "$search_input" != "!list" ]; then
			if [[ "$doubles" == true ]]; then
				for i in "${!entrants_lc_name2id[@]}"; do
					IFS=' + ' read -ra DUBS_TAGS <<< "$i"
					for j in "${DUBS_TAGS[@]}"; do
						if [[ "$search_input" == "$j" ]]; then
							search_match="$i"
						fi
					done
				done
			else
				for i in "${!entrants_lc_name2id[@]}"; do
					if [[ "$search_input" == "$i" ]]; then
						search_match="$i"
					fi
				done
			fi
		fi
		if [[ ! -z $search_match ]]; then
			search_id="${entrants_lc_name2id[$search_match]}"
			selected_sets=()
			for i in $(seq 0 $((${#set_id[@]} - 1))); do
				if [[ "$search_id" == "${set_player1[$i]}" || "$search_id" == "${set_player2[$i]}" ]]; then
					selected_sets+=("${set_id[$i]}")
				fi
			done
			debug "${selected_sets[*]}"

			player_set_options_id=()
			player_set_options_text=()

			for i in $(seq 0 $((${#set_id[@]} - 1))); do
				for j in "${selected_sets[@]}"; do
					if [[ "$j" == "${set_id[$i]}" ]]; then
						player_set_options_id+=("${set_id[$i]}")
						player_set_options_text+=("${entrants[${set_player1[$i]}]} vs ${entrants[${set_player2[$i]}]} - ${set_round[$i]}")
					fi
				done
			done

			chosen_set_id=""

			PS3='Choose the appropriate set: '
			# Setting COLUMNS for single column SELECTS
			COLUMNS=12
			select opt in "${player_set_options_text[@]}"; do
				if [[ $REPLY =~ ^-?[0-9]+$ && $REPLY -le ${#player_set_options_text[@]} && $REPLY > 0 ]]; then
					player_set_index=$(($REPLY - 1))
					chosen_set_id="${player_set_options_id[$player_set_index]}"
					break
				else
					echo -e "${ORANGE}Selection is invalid!${NC}"
				fi
			done

			entrant1_alt_text=""
			entrant2_alt_text=""
			title_full=""

			for i in $(seq 0 $((${#set_id[@]} - 1))); do
				if [[ "$chosen_set_id" == "${set_id[$i]}" ]]; then

					# Customize alt text
					if [[ "$doubles" == true ]]; then # Doubles (team color)
						doubles_colors=("[R]ed" "[G]reen" "[B]lue")
						PS3="Choose the team color for ${entrants[${set_player1[$i]}]}: "
						COLUMNS=12
						select opt in "${doubles_colors[@]}"; do
							case "$REPLY" in
								[1rR] )
									doubles_colors=( "${doubles_colors[@]/'[R]ed'/}" )
									entrant1_alt_text=" (R)"
									break
								;;
								[2gG] )
									doubles_colors=( "${doubles_colors[@]/'[G]reen'/}" )
									entrant1_alt_text=" (G)"
									break
								;;
								[3bB] )
									doubles_colors=( "${doubles_colors[@]/'[B]lue'/}" )
									entrant1_alt_text=" (B)"
									break
								;;
								* ) echo -e "${ORANGE}Selection is invalid!${NC}"
								;;
							esac
						done
						PS3="Choose the team color for ${entrants[${set_player2[$i]}]}: "
						COLUMNS=12
						select opt in "${doubles_colors[@]}"; do
							if [[ -n $opt ]]; then
								case "${REPLY^^}" in
									${doubles_colors[0]:1:1} )
										entrant2_alt_text=" (${doubles_colors[0]:1:1})"
										break
									;;
									${doubles_colors[1]:1:1} )
										entrant2_alt_text=" (${doubles_colors[1]:1:1})"
										break
									;;
									[12] )
										entrant2_alt_text=" (${doubles_colors[$(($REPLY - 1))]:1:1})"
										break
									;;
									* ) echo -e "${ORANGE}Selection is invalid!${NC}"
									;;
								esac
							else
								echo -e "${ORANGE}Selection is invalid!${NC}"
							fi
						done
					else # Singles (characters + colors for any characters both players played)
						characters_player1=()
						character_text_player1=()
						characters_player2=()
						character_text_player2=()
						PS3="Choose the characters played by ${entrants[${set_player1[$i]}]}: "
						unset COLUMNS
						select opt in "${characters[@]}"; do
							if [[ $REPLY =~ ^[0-9\ ]+$ && -n $REPLY ]]; then
								characters_player1=($REPLY)
								test_results=0
								for test_item in "${characters_player1[@]}"; do
									if (( "$test_item" < 1 || "$test_item" > "${#characters[@]}" )); then
										test_results=1
									fi
								done
								debug "$test_results"
								if [[ $test_results == 0 ]]; then
									break
								else
									echo -e "${ORANGE}Input is invalid! Be sure each character choice is within the correct range of numbers.${NC}"
								fi
							else
								echo -e "${ORANGE}Input is invalid! Be sure to type each character's number, separated by spaces.${NC}"
							fi
						done
						PS3="Choose the characters played by ${entrants[${set_player2[$i]}]}: "
						unset COLUMNS
						select opt in "${characters[@]}"; do
							if [[ $REPLY =~ ^-?[0-9\ ]+$ && -n $REPLY ]]; then
								characters_player2=($REPLY)
								test_results=0
								for test_item in "${characters_player2[@]}"; do
									if (( "$test_item" < 1 || "$test_item" > "${#characters[@]}" )); then
										test_results=1
									fi
								done
								if [[ $test_results == 0 ]]; then
									break
								else
									echo -e "${ORANGE}Input is invalid! Be sure each character choice is within the correct range of numbers.${NC}"
								fi
							else
								echo -e "${ORANGE}Input is invalid! Be sure to type each character's number, separated by spaces.${NC}"
							fi
						done
						for j in "${characters_player1[@]}"; do
							char_index=$(($j - 1))
							character_text_player1+=("${characters[$char_index]}")
						done
						for j in "${characters_player2[@]}"; do
							char_index=$(($j - 1))
							character_text_player2+=("${characters[$char_index]}")
						done
						characters_overlap=()
						# Check if the players played same character, allow for color selection
						for j in "${characters_player1[@]}"; do
							for k in "${characters_player2[@]}"; do
								if [[ "$j" == "$k" ]]; then
									characters_overlap+=("$j")
								fi
							done
						done
						if [ ${#characters_overlap[@]} -ne 0 ]; then
							# Ask for colors for each player for each duplicate character
							for dupe in "${characters_overlap[@]}"; do
								char_index=$(($dupe - 1))
								dupe_colors=(${character_colors[char_index]})
								PS3="Choose the color ${characters[$char_index]} played by ${entrants[${set_player1[$i]}]}: "
								COLUMNS=12
								select opt in "${dupe_colors[@]}"; do
									if [[ $REPLY =~ ^-?[0-9]+$ && $REPLY -le ${#dupe_colors[@]} && $REPLY > 0 ]]; then
										for char_pos in $(seq 0 $((${#character_text_player1[@]} - 1))); do
											if [[ "${character_text_player1[$char_pos]}" == "${characters[$char_index]}" ]]; then
												character_text_player1[$char_pos]="$opt ${character_text_player1[$char_pos]}"
											fi
										done
										dupe_colors=( "${dupe_colors[@]/$opt/}" )
										break
									else
										echo -e "${ORANGE}Input is invalid!${NC}"
									fi
								done
								PS3="Choose the color ${characters[$char_index]} played by ${entrants[${set_player2[$i]}]}: "
								COLUMNS=12
								select opt in "${dupe_colors[@]}"; do
									if [[ $REPLY =~ ^-?[0-9]+$ && $REPLY -le ${#dupe_colors[@]} && $REPLY > 0 && -n $opt ]]; then
										for char_pos in $(seq 0 $((${#character_text_player2[@]} - 1))); do
											if [[ "${character_text_player2[$char_pos]}" == "${characters[$char_index]}" ]]; then
												character_text_player2[$char_pos]="$opt ${character_text_player2[$char_pos]}"
											fi
										done
										break
									else
										echo -e "${ORANGE}Input is invalid!${NC}"
									fi
								done
							done
						fi

						# Output text array to correct format (comma separated) and apply to alt text
						text_holder_p1=""
						for text_id in $(seq 0 $((${#character_text_player1[@]} - 1))); do
							if [[ $text_id != $((${#character_text_player1[@]} - 1)) ]]; then
								text_holder_p1+="${character_text_player1[$text_id]}, "
							else
								text_holder_p1+="${character_text_player1[$text_id]}"
							fi
						done
						entrant1_alt_text=" ($text_holder_p1)"

						text_holder_p2=""
						for text_id in $(seq 0 $((${#character_text_player2[@]} - 1))); do
							if [[ $text_id != $((${#character_text_player2[@]} - 1)) ]]; then
								text_holder_p2+="${character_text_player2[$text_id]}, "
							else
								text_holder_p2+="${character_text_player2[$text_id]}"
							fi
						done
						entrant2_alt_text=" ($text_holder_p2)"

					fi

					title_full="${title_tournament} ${title_event} - ${entrants[${set_player1[$i]}]}${entrant1_alt_text} vs ${entrants[${set_player2[$i]}]}${entrant2_alt_text} - ${set_round[$i]}"

				fi
			done

			echo -e "${GREEN}$title_full${NC}"

			debug "$video $video_folder/$title_full.$extension"

			mv "$video" "$video_folder/$title_full.$extension"

			break
		elif [[ "$search_input" == "!list" ]]; then
			echo ""
			for value in "${entrants[@]}"; do
				printf "%-8s\n" "${value}"
			done | column
			echo ""
		else
			echo -e "${ORANGE}Entry is invalid! Type \"${L_BLUE}!list${ORANGE}\" to see a lits of all players in the bracket if you need help.${NC}"
		fi
	done

	if [[ $preview_mode == true ]]; then
		kill $preview_pid
	fi

done
