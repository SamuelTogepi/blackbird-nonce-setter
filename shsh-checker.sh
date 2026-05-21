#!/bin/bash

clear
echo "========================================================================="
echo "              Samuel's SHSH & IPSW Component Patching Tool"
echo "                (iPad 6th Gen iPad7,5 / iPad7,6 Edition)"
echo "========================================================================="
echo ""

# Ensure we are running on macOS or Linux
OS="$(uname)"
if [[ "$OS" != "Darwin" && "$OS" != "Linux" ]]; then
    echo "[#] Error: This script requires macOS or Linux."
    exit 1
fi

IMG4TOOL="/usr/local/bin/img4tool"
if [ ! -f "$IMG4TOOL" ]; then
    if command -v img4tool &> /dev/null; then
        IMG4TOOL="img4tool"
    else
        echo "[#] Error: img4tool is not installed. Please install it first or run Déverser."
        exit 1
    fi
fi

# ==========================================
# MODULE 1: SHSH Verification
# ==========================================
echo "------------------------------------------------------------------------"
echo " [1/3] SHSH Verification Module"
echo "------------------------------------------------------------------------"
echo "[?] Drag and drop your target SHSH blob file here and press Enter:"
read -r shsh
shsh=$(echo "$shsh" | sed -e 's/^['\''"]//' -e 's/['\''"]$//' -e 's/\\//g' -e 's/[[:space:]]*$//')

if [ ! -f "$shsh" ]; then
    echo "[#] Error: Blob file not found."
    exit 1
fi

echo "[*] Checking signature integrity with img4tool..."
$IMG4TOOL -s "$shsh" &> /dev/null
if [ $? -ne 0 ]; then
    echo "[#] Error: img4tool reports this SHSH signature/ticket is corrupted or invalid."
    exit 1
fi

# Parse ECID and Generator
ecid=$($IMG4TOOL -s "$shsh" | grep "ECID" | cut -d' ' -f2)
generator=$(grep -A 1 -i "generator" "$shsh" | grep "<string>0x" | sed -E 's/.*<string>(0x[0-9a-fA-F]+)<\/string>.*/\1/')

echo "[!] Blob Verification: SUCCESS"
echo "[!] ECID inside Blob: $ecid"
echo "[!] Generator inside Blob: $generator"
echo ""

# ==========================================
# MODULE 2: Component Mismatch Fix (IPSW Patching)
# ==========================================
echo "------------------------------------------------------------------------"
echo " [2/3] Component Hash Fix (AOP Patching & Hash Injection)"
echo "------------------------------------------------------------------------"
echo "Do you want to patch your target IPSW using iPad7,5 / iPad7,6 iOS 17.7 base components? (y/n)"
read -r patch_choice

if [[ "$patch_choice" =~ ^[Yy](es)?$ ]]; then
    echo "[?] Drag and drop your original older target IPSW file (e.g., iOS 14.x/15.x) and press Enter:"
    read -r ipsw_target
    ipsw_target=$(echo "$ipsw_target" | sed -e 's/^['\''"]//' -e 's/['\''"]$//' -e 's/\\//g' -e 's/[[:space:]]*$//')

    if [ ! -f "$ipsw_target" ]; then
        echo "[#] Error: Target IPSW not found."
        exit 1
    fi

    # Define Apple official URL for iOS 17.7 on iPad 6 (ASTC TouchID architecture)
    BASE_IPSW_URL="https://updates.cdn-apple.com/2024FallFCS/fullrestores/062-78995/AE33744E-AF74-4486-9C78-56519F307FDB/iPad_64bit_TouchID_ASTC_17.7_21H16_Restore.ipsw"

    echo ""
    echo "[*] Creating working directories..."
    rm -rf tmp_target_extract tmp_base_extract
    mkdir -p tmp_target_extract tmp_base_extract
    
    echo "[*] Fetching BuildManifest from Apple's signed iOS 17.7 IPSW..."
    sudo ./bin/pzb -g BuildManifest.plist "$BASE_IPSW_URL"
    if [ ! -f "BuildManifest.plist" ]; then
        echo "[#] Error: Failed to fetch BuildManifest.plist from Apple's CDN."
        rm -rf tmp_target_extract tmp_base_extract
        exit 1
    fi
    mv BuildManifest.plist tmp_base_extract/BuildManifest.plist

    echo "[*] Parsing iOS 17.7 BuildManifest dynamically for iPad7,5 / iPad7,6 files..."
    
    # Extract filenames using python
    python3 -c "
import plistlib
with open('tmp_base_extract/BuildManifest.plist', 'rb') as f:
    plist = plistlib.load(f)
for identity in plist.get('BuildIdentities', []):
    manifest = identity.get('Manifest', {})
    
    # Grab RestoreRamDisk
    if 'RestoreRamDisk' in manifest:
        print(f'RESTORE_RD=' + manifest['RestoreRamDisk']['Info']['Path'])
    
    # Grab AOP component
    if 'AOP' in manifest:
        print(f'AOP_PATH=' + manifest['AOP']['Info']['Path'])
        
    # Grab iBSS & iBEC
    if 'iBSS' in manifest:
        print(f'IBSS_PATH=' + manifest['iBSS']['Info']['Path'])
    if 'iBEC' in manifest:
        print(f'IBEC_PATH=' + manifest['iBEC']['Info']['Path'])
    break
" > parsed_components.txt

    # Parse key variables
    RESTORE_RD=$(grep "RESTORE_RD=" parsed_components.txt | cut -d'=' -f2)
    AOP_PATH=$(grep "AOP_PATH=" parsed_components.txt | cut -d'=' -f2)
    IBSS_PATH=$(grep "IBSS_PATH=" parsed_components.txt | cut -d'=' -f2)
    IBEC_PATH=$(grep "IBEC_PATH=" parsed_components.txt | cut -d'=' -f2)
    rm -f parsed_components.txt

    echo "[!] Extracted target paths from iOS 17.7 base manifest:"
    echo "    - AOP Path: $AOP_PATH"
    echo "    - Restore Ramdisk: $RESTORE_RD"
    echo "    - iBSS: $IBSS_PATH"
    echo "    - iBEC: $IBEC_PATH"
    echo ""

    # Partially download these specific components from the Apple server using pzb
    echo "[*] Fetching AOP firmware component from iOS 17.7..."
    sudo ./bin/pzb -g "$AOP_PATH" "$BASE_IPSW_URL"
    mkdir -p tmp_base_extract/Firmware/AOP/
    mv "$(basename "$AOP_PATH")" tmp_base_extract/Firmware/AOP/

    echo "[*] Fetching Restore Ramdisk from iOS 17.7..."
    sudo ./bin/pzb -g "$RESTORE_RD" "$BASE_IPSW_URL"
    mv "$(basename "$RESTORE_RD")" tmp_base_extract/

    echo "[*] Fetching Trustcache for the Restore Ramdisk..."
    sudo ./bin/pzb -g "${RESTORE_RD}.trustcache" "$BASE_IPSW_URL"
    mv "$(basename "${RESTORE_RD}.trustcache")" tmp_base_extract/

    echo "[*] Unzipping original target IPSW structure..."
    unzip -q "$ipsw_target" -d tmp_target_extract/
    chmod -R +w tmp_target_extract tmp_base_extract 2>/dev/null

    echo "[*] Swapping AOP firmware binary into target IPSW..."
    cp -f "tmp_base_extract/Firmware/AOP/$(basename "$AOP_PATH")" tmp_target_extract/Firmware/AOP/aopfw-ipad7baop.im4p

    echo "[*] Swapping iOS 17.7 Restore Ramdisk into target IPSW..."
    # Replace target's original ramdisk with the one we extracted
    orig_target_rd=$(find tmp_target_extract/ -name "0*.dmg" | head -n 1)
    if [ -f "$orig_target_rd" ]; then
        cp -f "tmp_base_extract/$(basename "$RESTORE_RD")" "$orig_target_rd"
        cp -f "tmp_base_extract/$(basename "${RESTORE_RD}.trustcache")" "${orig_target_rd}.trustcache"
    fi

    echo "[*] Writing Python helper to patch BuildManifest.plist hashes..."
    cat << 'EOF' > patch_manifest.py
import sys
import plistlib

manifest_target_path = sys.argv[1]
manifest_base_path = sys.argv[2]

try:
    with open(manifest_target_path, 'rb') as f:
        data_target = f.read()
        fmt_target = plistlib.detect_format(data_target)
        plist_target = plistlib.loads(data_target)

    with open(manifest_base_path, 'rb') as f:
        plist_base = plistlib.load(f)

    aop_base = None
    for identity in plist_base.get('BuildIdentities', []):
        manifest = identity.get('Manifest', {})
        if 'AOP' in manifest:
            aop_base = manifest['AOP']
            break

    if not aop_base:
        print("[-] Error: AOP key not found in base BuildManifest.")
        sys.exit(1)

    patched_count = 0
    for identity in plist_target.get('BuildIdentities', []):
        manifest = identity.get('Manifest', {})
        if 'AOP' in manifest:
            orig_aop = manifest['AOP']
            
            # Perform clean injection swap
            if 'Digest' in aop_base:
                orig_aop['Digest'] = aop_base['Digest']
            if 'Info' in aop_base:
                orig_aop['Info'] = aop_base['Info'].copy()
                orig_aop['Info']['Path'] = "Firmware/AOP/aopfw-ipad7baop.im4p"
            if 'Trusted' in aop_base:
                orig_aop['Trusted'] = aop_base['Trusted']
                
            manifest['AOP'] = orig_aop
            patched_count += 1

    if patched_count == 0:
        print("[-] Warning: No target AOP key found to replace.")
        sys.exit(1)

    with open(manifest_target_path, 'wb') as f:
        plistlib.dump(plist_target, f, fmt=fmt_target)

    print(f"[+] Successfully patched AOP manifest signatures ({patched_count} build identities).")
except Exception as e:
    print(f"[-] Python error during plist edit: {e}")
    sys.exit(1)
EOF

    echo "[*] Executing BuildManifest hash injection..."
    python3 patch_manifest.py tmp_target_extract/BuildManifest.plist tmp_base_extract/BuildManifest.plist
    
    if [ $? -ne 0 ]; then
        echo "[#] Error: BuildManifest patch failed. Aborting."
        rm -f patch_manifest.py
        rm -rf tmp_target_extract tmp_base_extract
        exit 1
    fi
    rm -f patch_manifest.py

    echo "[*] Repacking patched IPSW (this may take a couple of minutes)..."
    patched_filename="iPad6_PATCHED.ipsw"
    
    rm -f "../$patched_filename"
    cd tmp_target_extract || exit 1
    zip -q -r "../$patched_filename" .
    cd ..

    echo "[!] Patched IPSW successfully written to: $patched_filename"
    
    # Cleanup working directories
    echo "[*] Cleaning up temporary files..."
    rm -rf tmp_target_extract tmp_base_extract
else
    echo "[*] Skipping IPSW patching."
fi

# ==========================================
# MODULE 3: Final Execution Directions
# ==========================================
echo ""
echo "------------------------------------------------------------------------"
echo " [3/3] Execution Guidelines"
echo "------------------------------------------------------------------------"
if [ -f "iPad6_PATCHED.ipsw" ]; then
    echo "Run the restore using your valid SHSH blob and the newly patched IPSW:"
    echo ""
    echo "sudo ./bin/turdus_merula -w --load-shsh $shsh $(pwd)/iPad6_PATCHED.ipsw"
else
    echo "No patched IPSW was created."
fi
echo "========================================================================="
