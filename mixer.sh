#!/bin/bash

source "$(dirname "$0")/util.sh"

init() {

	declare -r client_id="f03f67cb7e2245019571bce6eac4a474"
	declare -r spotify_api_base="https://api.spotify.com/v1"
	declare -r spotify_token_endpoint="https://accounts.spotify.com/api/token"
	declare -r config_file=".config"
	declare -ra required_packages=("curl" "jq")

	declare access_token
	declare refresh_token
	declare -i expires_on
	declare input_playlists
	declare output_playlist
	declare -a tracklist

	clear_term

	check_required_packages "${required_packages[@]}"

	load_variables_from_file "$config_file"

	fetch_input_playlists

	update_output_playlist

	finished
}

refresh_access_token_if_needed() {

	declare -i current_time
	current_time=$(date +%s)

	if [ "$current_time" -gt $((expires_on - 60)) ]; then
		echo -n "refreshing access token..."

		declare res
		res=$(curl -s -X "POST" "$spotify_token_endpoint" \
			-H "Content-Type: application/x-www-form-urlencoded" \
			-d "grant_type=refresh_token&refresh_token=$refresh_token&client_id=$client_id")

		declare error
		declare error_description
		declare new_access_token
		declare new_refresh_token
		declare -i expires_in

		error=$(echo "$res" | jq -r ".error")
		error_description=$(echo "$res" | jq -r ".error_description")

		if [ "$error" != "null" ]; then
			echo ""
			echo "error: received the following from spotify: [$error] $error_description"
			exit 1
		fi

		new_access_token=$(echo "$res" | jq -r ".access_token")
		new_refresh_token=$(echo "$res" | jq -r ".refresh_token")
		expires_in=$(echo "$res" | jq -r ".expires_in")

		# set the new values for access token and expiry time
		access_token="$new_access_token"
		expires_on=$(calculate_expires_on "$expires_in")

		# if there is a new refresh token, update the old one
		if [ "$new_refresh_token" != "null" ]; then
			refresh_token="$new_refresh_token"
		fi

		echo "ok"

		save_variables_to_file "$config_file"
	fi
}

fetch_input_playlists() {

	refresh_access_token_if_needed

	# input field separator, default is a space but input_playlists are separated with ,
	IFS=","

	# loop over the input_playlists read from $config
	for playlist_id in $input_playlists; do

		# unset IFS immediately otherwise it messes up the json response $res
		unset IFS

		echo -n "fetching tracks from $playlist_id..."

		fetch_playlist_tracks "$playlist_id"

		echo "ok"
	done
}

fetch_playlist_tracks() {

	declare playlist_id="$1"
	declare next="$2"

	declare request_url
	declare res

	# if the next parameter is set in this function (happens when pagination is needed), use it as the request url
	if [ -n "$next" ]; then
		request_url="$next"
	else
		request_url="$spotify_api_base/playlists/$playlist_id/tracks?limit=50&fields=next,items(is_local,track.uri)"
	fi

	res=$(curl -s -X "GET" "$request_url" \
		-H "Authorization: Bearer $access_token")

	declare error
	declare error_description
	declare next

	error=$(echo "$res" | jq -r ".error.status")
	error_description=$(echo "$res" | jq -r ".error.message")
	next=$(echo "$res" | jq -r ".next")

	if [ "$error" != "null" ]; then
		echo ""
		echo "error: received the following from spotify: [$error] $error_description"
		exit 1
	fi

	add_tracks_to_tracklist "$res"

	if [ "$next" != "null" ]; then
		echo -n "..."
		fetch_playlist_tracks "$playlist_id" "$next"
	fi
}

add_tracks_to_tracklist() {

	declare res="$1"

	# for each track if it is not a local only track, add its uri to the tracklist array
	while read -r track; do

		declare track_uri
		declare is_local

		track_uri=$(echo "$track" | jq -r ".track.uri")
		is_local=$(echo "$track" | jq -r ".is_local")

		if [ "$is_local" == "false" ]; then
			tracklist+=("$track_uri")
		fi

	done < <(echo "$res" | jq -c ".items[]")
}

update_output_playlist() {

	declare -i offset="$1"
	declare uris_to_add

	# subset the tracklist to a maximum of 100 and comma seperate them
	uris_to_add=${tracklist[*]:offset:100}
	uris_to_add=${uris_to_add//\ /,}

	declare method

	if [ "$offset" == 0 ]; then
		# if the offset is 0, the method will be PUT to replace the tracks in the playlist
		# this empties the output playlist while also adding the supplied tracks
		method="PUT"
		echo -n "adding tracks to $output_playlist..."
	else
		# if the offset is not zero, the playlist has already been cleared and the first songs are already added
		# we can use the method POST to add more tracks
		method="POST"
		echo -n "..."
	fi

	# echo ""
	# echo "$method"
	# echo "$spotify_api_base/v1/playlists/$output_playlist/tracks?uris=$uris_to_add"

	declare res
	res=$(curl -s -X "$method" "$spotify_api_base/playlists/$output_playlist/tracks?uris=$uris_to_add" \
		-H "Authorization: Bearer $access_token")

	declare error
	declare error_description

	error=$(echo "$res" | jq -r ".error.status")
	error_description=$(echo "$res" | jq -r ".error.message")

	if [ "$error" != "null" ]; then
		echo ""
		echo "error: received the following from spotify: [$error] $error_description"
		exit 1
	fi

	# if the length of the tracklist is longer than the current offset + 100 we call this function again with the new offset
	# otherwise we are done
	if [ "${#tracklist[@]}" -gt $((offset + 100)) ]; then
		update_output_playlist "$((offset + 100))"
	else
		echo "ok"
	fi
}

finished() {
	echo "mixer.sh executed successfully!"
	exit 0
}

init
