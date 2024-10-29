#!/bin/bash

clear_term() {
	clear

	basename "$0"
	echo ""
	echo "     __     _ __               _"
	echo " ___/ /__ _(_) /_ ________ _  (_)_ _____ ____"
	echo "/ _  / _ \`/ / / // /___/  ' \/ /\ \ / -_) __/"
	echo "\_,_/\_,_/_/_/\_, /   /_/_/_/_//_\_\\__/_/"
	echo "             /___/"
	echo ""
}

load_variables_from_file() {

	declare config_file="$1"

	echo -n "loading configuration from $config_file..."

	# shellcheck source=.config
	source "$config_file"

	declare vars=("access_token" "refresh_token" "expires_on" "input_playlists" "output_playlist")

	# Check if required variables are present
	for var in "${vars[@]}"; do
		if [ -z "${!var}" ]; then
			echo ""
			echo "error: $var is not set in $config_file."
			exit 1
		fi
	done

	echo "ok"
}

save_variables_to_file() {

	declare config_file="$1"

	echo -n "saving configuration to $config_file..."

	dit moet beter
	{
		echo "access_token=${access_token:?}"
		echo "refresh_token=${refresh_token:?}"
		echo "expires_on=${expires_on:?}"
		echo "input_playlists=${input_playlists:?}"
		echo "output_playlist=${output_playlist:?}"
	} >"$config_file"

	chmod 600 "$config_file"

	echo "ok"
}

check_required_packages() {

	declare -a packages=("$@")

	for package in "${packages[@]}"; do
		if ! command -v "$package" >/dev/null 2>&1; then
			echo "error: $package is not installed, please install it and try again"
			exit 1
		fi
	done
}

calculate_expires_on() {

	declare -i expires_in="$1"
	declare -i current_time

	current_time=$(date +%s)
	echo $((current_time + expires_in))
}

base64_url_encode() {
	local input="$1"

	# Replace / with _ and + with - and remove =
	input=${input//\//_}
	input=${input//+/-}
	input=${input//=/}

	echo -n "$input"
}
