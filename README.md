# daily-mixer

<img src="./cover.jpg" alt="daily mixer" width="196" height="196" style="text-align: center;">

A pair of bash scripts to combine multiple Spotify playlists into one big playlist, a monolist! 

Can be used to combine the songs of any public or private playlists into a singular playlist. Does not require user interaction once `setup.sh` has been completed, allowing for automation using something like cron. Made this for myself to have one big playlist which updates every day consisting of the daily mixes provided by Spotify. 

All this because we can't play folders on the Spotify mobile app :(

## Required

- Spotify account
- Bash
- `curl`, `openssl`, `base64` and `jq`

## Usage

1. Clone this repository
1. Execute the `setup.sh` script and follow the instructions
1. Execute the `mixer.sh` script to combine your playlists! 

**Note:** The playlist created during setup will be completely overwritten anytime `mixer.sh` is run. Add songs to it manually at your own risk.
