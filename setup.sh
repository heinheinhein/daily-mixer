#!/bin/bash

source "$(dirname "$0")/util.sh"

init() {

	declare -r client_id="f03f67cb7e2245019571bce6eac4a474"
	declare -r scope="playlist-read-private playlist-modify-public playlist-modify-private ugc-image-upload"
	declare -r redirect_uri="https://heinheinhein.github.io/daily-mixer/"
	declare -r spotify_api_base="https://api.spotify.com/v1"
	declare -r spotify_authorize_endpoint="https://accounts.spotify.com/authorize"
	declare -r spotify_token_endpoint="https://accounts.spotify.com/api/token"
	declare -r config_file=".config"
	declare -ra required_packages=("curl" "openssl" "base64" "jq")
	declare -r cover_image="cover.jpg"

	declare code_verifier
	declare authorization_code
	declare access_token
	declare refresh_token
	declare -i expires_on
	declare input_playlists
	declare output_playlist
	declare user_id

	clear_term

	check_required_packages "${required_packages[@]}"

	get_authorization_code

	clear_term

	request_initial_access_token

	get_input_playlists

	clear_term

	get_output_playlist

	set_output_playlist_cover_image

	save_variables_to_file "$config_file"

	clear_term

	finished
}

get_authorization_code() {

	declare code_challenge
	declare state
	declare url_safe_scope

	# generate random code verifier
	code_verifier=$(openssl rand 64 | base64 -w 0)

	# encode it in websafe base64
	code_verifier=$(base64_url_encode "$code_verifier")

	# calculate sha256 hash and encode it in base64 and also encode it in websafe base64
	code_challenge=$(echo -n "$code_verifier" | openssl dgst -binary -sha256 | base64 -w 0)
	code_challenge=$(base64_url_encode "$code_challenge")

	# remove spaces from the scope, otherwise it breaks the url
	url_safe_scope=${scope// /%20}

	# generate a random state
	state=$(openssl rand -hex 3)

	echo "(1) open this url in your browser to athenticate with spotify:"
	echo "$spotify_authorize_endpoint?client_id=$client_id&response_type=code&redirect_uri=$redirect_uri&state=$state&scope=$url_safe_scope&code_challenge_method=S256&code_challenge=$code_challenge"
	echo ""

	echo "(2) confirm the state is $state"
	echo ""

	echo "(3) enter the authorization code"
	read -rp "authorization code: " authorization_code
}

request_initial_access_token() {
	echo -n "requesting initial access token..."

	declare res

	res=$(curl -s -X "POST" "$spotify_token_endpoint" \
		-H "Content-Type: application/x-www-form-urlencoded" \
		-d "grant_type=authorization_code&code=$authorization_code&redirect_uri=$redirect_uri&client_id=$client_id&code_verifier=$code_verifier")

	declare error
	declare error_description
	declare new_access_token
	declare new_refresh_token
	declare expires_in

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

	access_token="$new_access_token"
	refresh_token="$new_refresh_token"
	expires_on=$(calculate_expires_on "$expires_in")

	echo "ok"
}

get_input_playlists() {
	echo ""
	echo "enter the id's of the playlists you want to combine (comma-separated), for example: mGypjWz6TveoMVdtWwOGIF,8yeusmk87CO4XwzSAfdPvW,TlPxYAcXfI3eMfs2Iv9Gq7"
	echo "you can find the playlist id's in the url on spotify's web player (https://open.spotify.com/) when navigating to a playlist"
	echo "alternatively, you can type 'list' to list your playlists and their id's"

	read -rp "id's: " new_input_playlists

	if [ "$new_input_playlists" == "list" ]; then
		get_user_playlists
		get_input_playlists
	else
		input_playlists="$new_input_playlists"
	fi
}

get_user_playlists() {
	echo -n "fetching user playlists..."

	# get the current user's playlists (50 is the maximum, otherwise pagination is needed)
	declare res
	res=$(curl -s -X "GET" "$spotify_api_base/me/playlists?limit=50" \
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

	echo "ok"
	echo ""

	# for each playlist print its name and id
	echo "$res" | jq -c ".items[]" | while read -r item; do
		declare name
		declare id

		name=$(echo "$item" | jq -r ".name")
		id=$(echo "$item" | jq -r ".id")

		echo "$name [$id]"
	done
}

get_output_playlist() {

	declare output_playlist_name
	declare output_playlist_public="true"
	declare tmp_output_playlist_visibility
	declare confirmed

	echo "enter the name of the output playlist (where all the songs from the selected playlists will end up in)"
	read -rp "name: " output_playlist_name
	echo ""
	echo "do you want this playlist to be public or private? (default is public)"
	read -rp "(public/private): " tmp_output_playlist_visibility

	if [ "$tmp_output_playlist_visibility" == "private" ]; then
		output_playlist_public="false"
	fi

	echo ""
	echo "your choices"
	echo "playlist name: $output_playlist_name"
	echo "public playlist: $output_playlist_public"

	read -rp "confirm (yes/no): " confirmed
	echo ""

	if [ "$confirmed" == "yes" ]; then
		create_output_playlist "$output_playlist_name" "$output_playlist_public"
	else
		get_output_playlist
	fi
}

create_output_playlist() {

	declare name="$1"
	declare public="$2"

	get_user_id

	echo -n "creating output playlist..."

	declare res
	res=$(curl -s -X "POST" "$spotify_api_base/users/$user_id/playlists" \
		-H "Content-Type: application/json" \
		-H "Authorization: Bearer $access_token" \
		-d "{\"name\": \"$name\",\"public\":$public}")

	declare error
	declare error_description

	error=$(echo "$res" | jq -r ".error.status")
	error_description=$(echo "$res" | jq -r ".error.message")

	if [ "$error" != "null" ]; then
		echo ""
		echo "error: received the following from spotify: [$error] $error_description"
		exit 1
	fi

	output_playlist=$(echo "$res" | jq -r ".id")

	echo "ok"
}

get_user_id() {
	echo -n "fetching user id..."

	declare res
	res=$(curl -s -X "GET" "$spotify_api_base/me" \
		-H "Content-Type: application/json" \
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

	user_id=$(echo "$res" | jq -r ".id")

	echo "ok"
}

set_output_playlist_cover_image() {
	if [ -f "$cover_image" ]; then
		echo -n "uploading cover image..."

		declare image_data
		image_data=$(base64 -w 0 "$cover_image")

		declare res
		res=$(curl -s -X "PUT" "$spotify_api_base/playlists/$output_playlist/images" \
			-H "Authorization: Bearer $access_token" \
			-H "Content-Type: image/jpeg" \
			-d "$image_data")

		declare error
		declare error_description

		error=$(echo "$res" | jq -r ".error.status")
		error_description=$(echo "$res" | jq -r ".error.message")

		if [ -n "$res" ] && [ "$error" != "null" ]; then
			echo ""
			echo "error: received the following from spotify: [$error] $error_description"
			exit 1
		fi

		echo "ok"
	fi
}

finished() {
	echo "setup.sh executed successfully!"
	echo "you can now use mixer.sh to combine your selected playlists"
	exit 0
}

init
