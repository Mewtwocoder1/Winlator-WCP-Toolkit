#!/data/data/com.termux/files/usr/bin/bash

# --- Global Variables ---
DOWNLOAD_DIR=~/storage/shared/Download
TEMP_DIR=~/wcp_temp_extraction

# --- Helper Functions ---
print_header() {
    clear
    echo "=========================================="
    echo "     Winlator WCP Toolkit for Android     "
    echo "=========================================="
    echo
}

# --- Core Logic ---
initial_setup() {
    print_header
    echo "Performing first-time setup... This may take a few minutes."
    pkg update -y && pkg upgrade -y
    pkg install -y git tar zstd binutils python jq
    termux-setup-storage
    echo "Waiting for you to grant storage permission..."
    while [ ! -d "$DOWNLOAD_DIR" ]; do sleep 2; done
    echo "Storage permission granted!"; sleep 2
}

convert_component() {
    local archive_path="$1" comp_type="$2" decompress_prog="$3"
    local filename=$(basename "$archive_path")
    
    local version=$(echo "$filename" | sed -n 's/.*-\([0-9]\+\.[0-9.]*\(-[0-9A-Za-z]\+\)\?\)\.tar\..*/\1/p')
    if [[ -z "$version" ]]; then version="1.0"; fi

    echo "--- Processing [$comp_type]: $filename ---"
    rm -rf "$TEMP_DIR"; mkdir -p "$TEMP_DIR/staging"

    # Extract source directly into staging root
    tar --use-compress-program="$decompress_prog" -xf "$archive_path" -C "$TEMP_DIR/staging" --strip-components=1 2>/dev/null \
      || tar --use-compress-program="$decompress_prog" -xf "$archive_path" -C "$TEMP_DIR/staging"
    
    local work_dir="$TEMP_DIR/staging"
    local profile_path="$work_dir/profile.json"

    # Standardize DXVK/VKD3D DLL directories
    [ -d "$work_dir/x64" ] && mv "$work_dir/x64" "$work_dir/system32"
    [ -d "$work_dir/x32" ] && mv "$work_dir/x32" "$work_dir/syswow64"
    [ -d "$work_dir/x86" ] && mv "$work_dir/x86" "$work_dir/syswow64"

    # Create profile.json with valid integer versionCode
    jq -n --arg type "$comp_type" --arg name "$version" --arg desc "$comp_type $version" \
      '{type: $type, versionName: $name, versionCode: 1, description: $desc, files: []}' > "$profile_path"

    # Register DLL entries for DXVK/VKD3D
    if [[ "$comp_type" == "DXVK" || "$comp_type" == "VKD3D" ]]; then
        local dlls="d3d8 d3d9 d3d10 d3d10_1 d3d10core d3d11 d3d12 d3d12core dxgi"
        for dll in $dlls; do
            if [ -f "$work_dir/system32/$dll.dll" ]; then
                jq --arg src "system32/$dll.dll" --arg tgt "\${system32}/$dll.dll" '.files += [{"source":$src, "target":$tgt}]' "$profile_path" > tmp.json && mv tmp.json "$profile_path"
            fi
            if [ -f "$work_dir/syswow64/$dll.dll" ]; then
                jq --arg src "syswow64/$dll.dll" --arg tgt "\${syswow64}/$dll.dll" '.files += [{"source":$src, "target":$tgt}]' "$profile_path" > tmp.json && mv tmp.json "$profile_path"
            fi
        done
    fi

    # Pack directly from work_dir root using zstd compression
    local output_file="${filename%.tar.*}.wcp"
    echo "Creating $output_file..."
    tar --use-compress-program="zstd -19" -cf "$DOWNLOAD_DIR/$output_file" -C "$work_dir" .
    
    echo "--- Successfully created $output_file ---"
    rm -rf "$TEMP_DIR"
}

organize_downloads() {
    local source_files=("$@")
    local output_dir="$DOWNLOAD_DIR/_wcp_output"; local source_dir="$DOWNLOAD_DIR/_source_archives"
    mkdir -p "$output_dir" "$source_dir"
    
    echo "Organizing files..."
    for file in "${source_files[@]}"; do mv "$file" "$source_dir/" 2>/dev/null; done
    for wcp_file in "$DOWNLOAD_DIR"/*.wcp; do
        if [ -f "$wcp_file" ]; then mv "$wcp_file" "$output_dir/" 2>/dev/null; fi
    done
    echo "Moved .wcp files to '_wcp_output' and source archives to '_source_archives'."
}

batch_process() {
    print_header
    echo "Starting Batch Conversion... Looking for archives in: $DOWNLOAD_DIR"
    local processed_count=0; local source_files_to_move=()

    for file in "$DOWNLOAD_DIR"/*; do
        if [[ ! -f "$file" ]]; then continue; fi
        
        local processed=false
        if [[ "$file" == *.tar.gz ]]; then
            convert_component "$file" "DXVK" "d3d9 d3d10 d3d10_1 d3d10core d3d11 dxgi" "d3d8 d3d9 d3d10 d3d10_1 d3d10core d3d11 dxgi" "gunzip"
            processed=true
        elif [[ "$file" == *.tar.zst ]]; then
            convert_component "$file" "VKD3D" "d3d12 d3d12core" "d3d12 d3d12core" "unzstd"
            processed=true
        fi
        
        if [[ "$processed" == true ]]; then
            processed_count=$((processed_count + 1))
            source_files_to_move+=("$file")
        fi
    done

    if [[ "$processed_count" -gt 0 ]]; then
        echo -e "\nBatch processing complete. Processed $processed_count file(s)."
        organize_downloads "${source_files_to_move[@]}"
    else
        echo "No compatible archives (.tar.gz, .tar.zst) found in your Downloads folder."
    fi
    
    echo
    read -r -p "Press Enter to return to the menu..." _
}

# --- Main Menu ---
main_menu() {
    print_header
    echo "Please place your archives (.tar.gz, .tar.zst) in your phone's"
    echo "main 'Download' folder before starting."
    echo -e "\nSelect an option:"
    echo " 1. Batch Convert All Files in Download Folder"
    echo " q. Quit"
    echo
    
    # Prevent infinite loop on EOF/read failure
    if ! read -r -p "Enter your choice: " choice; then
        echo -e "\nExiting."
        exit 0
    fi

    case "$choice" in
        1) batch_process ;;
        q|Q) echo "Exiting."; exit 0 ;;
        *) 
           echo -e "\nInvalid choice."
           read -r -p "Press Enter to try again..." _
           ;;
    esac
}

# --- Script Entry Point ---
if [ ! -f ~/.wcp_tools_setup_complete ]; then
    initial_setup
    touch ~/.wcp_tools_setup_complete
fi

# Show menu loop
while true; do
    main_menu
done
