#!/bin/bash

cd "$(dirname "$0")" || exit 1

CONFIG_FILE="config.cfg"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Error: Configuration file $CONFIG_FILE not found."
    exit 1
fi

LOG_FILE="$MEDIA_DIR/organization_report.log"
mkdir -p "$MEDIA_DIR"

declare -i movies_count=0
declare -i series_count=0
declare -i music_count=0
declare -i misc_count=0

# --- Dependency Check ---
check_dependencies() {
    for cmd in "curl" "jq"; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Critical Error: '$cmd' is not installed."
            echo "Please run: sudo apt-get install $cmd"
            exit 1
        fi
    done
}

write_log() {
    local message="$1"
    local timestamp="$(date "+%Y-%m-%d %H:%M:%S")"
    echo "[$timestamp] $message" >> "$LOG_FILE"
}

clean_movie_name() {
    local name="$1"
    local clean="$(echo "$name" | tr '._' ' ')"
    clean="$(echo "$clean" | sed -E 's/([\[\(]?(19[0-9]{2}|20[0-2][0-9])[\]\)]?|1080p|720p|2160p|4k|bluray|brrip|web-dl|hdtv|x264|x265|hevc|yts).*/ /I')"
    clean="$(echo "$clean" | tr -d '[]()' | xargs)"
    echo "$clean"
}

process_movie() {
    local file="$1"
    local filename="$(basename "$file")"
    local ext="$(echo "$filename" | rev | cut -d'.' -f1 | rev | tr '[:upper:]' '[:lower:]')"
    local name_no_ext="$(echo "$filename" | rev | cut -d'.' -f2- | rev)"
    local clean_name="$(clean_movie_name "$name_no_ext")"
    
    local api_response="$(curl -s --max-time 10 "http://www.omdbapi.com/?apikey=${API_KEY}&t=$(echo "$clean_name" | jq -sRr @uri)")"
    local status="$(echo "$api_response" | jq -r '.Response' 2>/dev/null)"
    
    if [ "$status" = "True" ]; then
        local official_title="$(echo "$api_response" | jq -r '.Title'| tr '/' '-')"
        local year="$(echo "$api_response" | jq -r '.Year')"
        local genres="$(echo "$api_response" | jq -r '.Genre')"
        
        local main_genre="$(echo "$genres" | cut -d',' -f1 | xargs| tr '/' '-')"
        local dest_dir="$MEDIA_DIR/Movies/$main_genre"
        mkdir -p "$dest_dir"
        
        local new_name="${official_title} (${year}).${ext}"
        mv -n "$file" "$dest_dir/$new_name"
        write_log "MOVIE: Moved '$filename' -> '$dest_dir/$new_name'"
        ((movies_count++))
    else
        local dest_dir_uncategorized="$MEDIA_DIR/Movies/Uncategorized"
        mkdir -p "$dest_dir_uncategorized"
        mv -n "$file" "$dest_dir_uncategorized/"
        write_log "MOVIE (NOT FOUND): Moved '$filename' -> '$dest_dir_uncategorized/'"
        ((movies_count++))
    fi
}

process_series() {
    local file="$1"
    local filename="$(basename "$file")"
    local ext="$(echo "$filename" | rev | cut -d'.' -f1 | rev | tr '[:upper:]' '[:lower:]')"
    local clean_name="$(echo "$filename" | tr '._' ' ')"

    local name=""
    local season=""
    local episode=""

    if [[ "$clean_name" =~ ^(.*)[sS]([0-9]+)[eE]([0-9]+)(.*)$ ]]; then
        name="$(echo "${BASH_REMATCH[1]}" | xargs)"
        season="$(echo "${BASH_REMATCH[2]}" | xargs)"
        episode="$(echo "${BASH_REMATCH[3]}" | xargs)"
    elif [[ "$clean_name" =~ ^(.*[^0-9])([0-9]+)[xX]([0-9]+)(.*)$ ]]; then
        name="$(echo "${BASH_REMATCH[1]}" | xargs)"
        season="$(echo "${BASH_REMATCH[2]}" | xargs)"
        episode="$(echo "${BASH_REMATCH[3]}" | xargs)"
    elif [[ "$clean_name" =~ ^(.*)[sS]eason[[:space:]]+([0-9]+)[[:space:]]+[eE]pisode[[:space:]]+([0-9]+)(.*)$ ]]; then
        name="$(echo "${BASH_REMATCH[1]}" | xargs)"
        season="$(echo "${BASH_REMATCH[2]}" | xargs)"
        episode="$(echo "${BASH_REMATCH[3]}" | xargs)"
    elif [[ "$clean_name" =~ ^(.*)[[:space:]]([0-9])([0-9]{2})[[:space:]](.*)$ ]]; then
        name="$(echo "${BASH_REMATCH[1]}" | xargs)"
        season="$(echo "${BASH_REMATCH[2]}" | xargs)"
        episode="$(echo "${BASH_REMATCH[3]}" | xargs)"
    elif [[ "$clean_name" =~ ^(.*)-[[:space:]]*([0-9]+)[[:space:]]*(.*)$ ]]; then
        local raw_anime_name="$(echo "${BASH_REMATCH[1]}" | sed -E 's/\[[^]]*\]//g' | xargs)"
        name="$(echo "$raw_anime_name" | sed 's/-//g' | xargs)"
        season="1"
        episode="$(echo "${BASH_REMATCH[2]}" | xargs)"
    fi

    if [ -n "$name" ] && [ -n "$season" ]; then
        local padded_season="$(printf "%02d" "$season")"
        local padded_episode="$(printf "%02d" "$episode")"

        local dest_dir="$MEDIA_DIR/Series/$name/Season $padded_season"
        mkdir -p "$dest_dir"

        local new_name="${name} - S${padded_season}E${padded_episode}.${ext}"
        mv -n "$file" "$dest_dir/$new_name"
        write_log "SERIES: Moved '$filename' -> '$dest_dir/$new_name'"
        ((series_count++))
    else
        local dest_dir_uncategorized="$MEDIA_DIR/Series/Uncategorized"
        mkdir -p "$dest_dir_uncategorized"
        mv -n "$file" "$dest_dir_uncategorized/"
        write_log "SERIES (UNCATEGORIZED): Moved '$filename' -> '$dest_dir_uncategorized/'"
        ((series_count++))
    fi
}

process_music() {
    local file="$1"
    local filename="$(basename "$file")"
    local ext="$(echo "$filename" | rev | cut -d'.' -f1 | rev | tr '[:upper:]' '[:lower:]')"
    local name_no_ext="$(echo "$filename" | rev | cut -d'.' -f2- | rev)"
    local clean_name="$(echo "$name_no_ext" | tr '._' ' ' | xargs)"

    local dest_dir=""
    local new_name=""

    if [[ "$clean_name" =~ ^(.*)-[[:space:]]*(.*)$ ]]; then
        local artist="$(echo "${BASH_REMATCH[1]}" | sed -E 's/^[0-9]+[[:space:]]*//' | xargs)"
        local title="$(echo "${BASH_REMATCH[2]}" | xargs)"
        
        dest_dir="$MEDIA_DIR/Music/$artist"
        new_name="${title}.${ext}"
        write_log "MUSIC: Moved '$filename' -> '$dest_dir/$new_name'"
    else
        dest_dir="$MEDIA_DIR/Music/Unsure"
        new_name="${clean_name}.${ext}"
        write_log "MUSIC (UNSURE): Moved '$filename' -> '$dest_dir/$new_name'"
    fi

    mkdir -p "$dest_dir"
    mv -n "$file" "$dest_dir/$new_name"
    ((music_count++))
}

process_misc() {
    local file="$1"
    local filename="$(basename "$file")"
    local ext="$(echo "$filename" | rev | cut -d'.' -f1 | rev | tr '[:upper:]' '[:lower:]')"

    if [ -x "$file" ] && [ ! -d "$file" ]; then
        mkdir -p "$MEDIA_DIR/Executables/"
        mv -n "$file" "$MEDIA_DIR/Executables/"
        write_log "EXECUTABLE (HAS PERMISSION): Moved '$filename' -> '$MEDIA_DIR/Executables/'"
        ((misc_count++))
        return
    fi

    case "$ext" in
        pdf|odt|doc|docx|xls|xlsx|txt|epub|csv)  
            mkdir -p "$MEDIA_DIR/Documents/"
            mv -n "$file" "$MEDIA_DIR/Documents/"
            write_log "DOCUMENT: Moved '$filename' -> '$MEDIA_DIR/Documents/'"
            ((misc_count++))
        ;;
        exe|msi|deb|dmg|sh|bat)
            mkdir -p "$MEDIA_DIR/Executables/"
            mv -n "$file" "$MEDIA_DIR/Executables/"
            write_log "EXECUTABLE (NO PERMISSION): Moved '$filename' -> '$MEDIA_DIR/Executables/'"
            ((misc_count++))
        ;;
        *)
            write_log "IGNORED: Unknown extension for file '$filename'"
        ;;
    esac
}

echo "------------------ STARTING ORGANIZATION ---------------------------"
check_dependencies

while read -r file; do
    filename="$(basename "$file")"
    ext="$(echo "$filename" | rev | cut -d'.' -f1 | rev | tr '[:upper:]' '[:lower:]')"
    
    case "$ext" in
        mkv|mp4|avi|m4v)
            if [[ "$filename" =~ [sS][0-9]+[eE][0-9]+ ]] || [[ "$filename" =~ [0-9]+[xX][0-9]+ ]]; then
                process_series "$file"
            else
                process_movie "$file"
            fi
            ;;
        mp3|flac|wav|m4a)
            process_music "$file"
            ;;
        *)
            process_misc "$file"
            ;;
    esac
done < <(find "$DOWNLOADS_DIR" -type f)

echo "------------------ ORGANIZATION COMPLETE ---------------------------"
echo "Movies processed:    $movies_count"
echo "Series processed:    $series_count"
echo "Music processed:     $music_count"
echo "Docs/Execs moved:    $misc_count"
echo "Detailed log saved to: $LOG_FILE"

write_log "Run completed: Movies [$movies_count], Series [$series_count], Music [$music_count], Misc [$misc_count]."
