#!/bin/bash

clear
echo "========================================================================="
echo "       blackbird-nonce-setter & turdus_merula (A9/A10)"
echo "            Target: iPad 6th Generation -> iOS 11.3"
echo "========================================================================="
echo ""

# Ensure we are running on macOS or Linux
OS="$(uname)"
if [[ "$OS" != "Darwin" && "$OS" != "Linux" ]]; then
    echo "[#] Error: turdus_merula requires macOS or Linux."
    exit 1
fi

# Locate turdus_merula directory
if [ -d "turdus_merula" ]; then
    cd files/turdus_merula || exit 1
elif [ -f "./files/turdus_merula/bin/turdus_merula" ]; then
    echo "[!] Already inside the turdus_merula directory."
else
    echo "[?] Please enter the path to your extracted turdus_merula folder:"
    read -r tm_path
    tm_path=$(echo "$tm_path" | sed -e 's/^['\''"]//' -e 's/['\''"]$//')
    cd "$tm_path" || { echo "[#] Error: Invalid directory."; exit 1; }
fi

# Apply permissions and clear extended attributes
echo "[*] Setting permissions on binaries..."
chmod +x ./bin/* 2>/dev/null
if [[ "$OS" == "Darwin" ]]; then
    echo "[*] Clearing extended attributes recursively on bin directory..."
    /usr/bin/xattr -cr ./bin 2>/dev/null
fi

# Step 1: Input IPSW
echo ""
echo "[?] Drag and drop your iOS 11.3 IPSW file into this window and press Enter:"
read -r ipsw
ipsw=$(echo "$ipsw" | sed -e 's/^['\''"]//' -e 's/['\''"]$//')

if [ ! -f "$ipsw" ]; then
    echo "[#] Error: IPSW file not found at path: $ipsw"
    exit 1
fi

# Step 2: Input & Validate 11.3 SHSH Blobs
echo ""
echo "[?] Drag and drop your iOS 11.3 SHSH/SHSH2 blob file into this window and press Enter:"
read -r shsh
shsh=$(echo "$shsh" | sed -e 's/^['\''"]//' -e 's/['\''"]$//')

if [ ! -f "$shsh" ]; then
    echo "[#] Error: Blob file not found at path: $shsh"
    exit 1
fi

# Extract and display generator
getGenerator() {
    grep -A 1 -i "generator" "$1" | grep "<string>0x" | sed -E 's/.*<string>(0x[0-9a-fA-F]+)<\/string>.*/\1/'
}
generator=$(getGenerator "$shsh")

if [ -z "$generator" ]; then
    echo "[#] Error: Failed to parse a valid generator from the blob."
    exit 1
fi
echo "[!] Parsed Generator: $generator"

# Step 3: Run turdusra1n with Generator (Blackbird Nonce Setter)
echo ""
echo "========================================================================="
echo " STEP 1/2: Exploiting & Setting Nonce with turdusra1n"
echo "========================================================================="
echo "[*] Run commands below when prompted:"
echo "[*] Triggering: ./files/turdus_merula/bin/turdusra1n -Db $generator"
echo "[*] Follow the on-screen instructions to enter DFU mode."
echo ""
read -p "Press Enter to execute exploit..." _

sudo ./files/turdus_merula/bin/turdusra1n -Db "$generator"

# Step 4: Execute Restore
echo ""
echo "========================================================================="
echo " STEP 2/2: Restoring with turdus_merula"
echo "========================================================================="
echo "[*] Triggering: ./files/turdus_merula/bin/turdus_merula -w --load-shsh $shsh $ipsw"
echo ""
read -p "Press Enter to start the restoration..." _

sudo ./files/turdus_merula/bin/turdus_merula -w --load-shsh "$shsh" "$ipsw"

echo ""
echo "[!] Restore command finished. Follow any remaining on-screen prompts in your terminal."
