# Auto Media Organizer (Bash)

A robust, automated Bash script that monitors a download directory and intelligently sorts movies, TV series, music, and documents into a clean, structured media library. 

## Features
* **Smart Parsing**: Uses Regex to extract clean titles and episode numbers from messy filenames.
* **API Integration**: Fetches official metadata (Year, Genre, Title) from the OMDb API for precise movie categorization.
* **Failsafe Logic**: Safely quarantines unrecognized files into `Uncategorized` folders instead of misplacing them.
* **Cron-Ready**: Designed to run silently in the background with absolute paths and built-in timestamped logging.

## Prerequisites
* Linux/macOS environment
* `curl` and `jq` installed (`sudo apt-get install curl jq`)
* A free [OMDb API Key](http://www.omdbapi.com/)

## Installation & Setup
1. Clone the repository.
2. Rename `config.cfg.example` to `config.cfg` and add your absolute paths and API key.
3. Make the script executable: `chmod +x organizer.sh`

## Automation (Set & Forget)
To run this script automatically every day at midnight, add it to your crontab (`crontab -e`):
`0 0 * * * /absolute/path/to/organizer.sh >/dev/null 2>&1`
