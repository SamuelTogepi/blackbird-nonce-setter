#!/bin/bash

clear
echo "========================================================================="
echo "              Samuel's SHSH & IPSW Component Patching Tool"
echo "                      (Automated Hash Injector)"
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
echo "[?] Drag and drop your iOS 11.3 SHSH blob file here and press Enter:"
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
echo "Do you want to patch your iOS 11.3 IPSW to fix the 'Failed to image4 manifest check [comp: AOP]' error? (y/n)"
read -r patch_choice

if [[ "$patch_choice" =~ ^[Yy](es)?$ ]]; then
    echo "[?] Drag and drop your original iOS 11.3 IPSW file and press Enter:"
    read -r ipsw_11
    ipsw_11=$(echo "$ipsw_11" | sed -e 's/^['\''"]//' -e 's/['\''"]$//' -e 's/\\//g' -e 's/[[:space:]]*$//')

    if [ ! -f "$ipsw_11" ]; then
        echo "[#] Error: iOS 11.3 IPSW not found."
        exit 1
    fi

    echo "[?] Drag and drop your signed iOS 17.7.11 IPSW file (downloaded from ipsw.me) and press Enter:"
    read -r ipsw_17
    ipsw_17=$(echo "$ipsw_17" | sed -e 's/^['\''"]//' -e 's/['\''"]$//' -e 's/\\//g' -e 's/[[:space:]]*$//')

    if [ ! -f "$ipsw_17" ]; then
        echo "[#] Error: iOS 17.7.11 IPSW not found."
        exit 1
    fi

    echo ""
    echo "[*] Creating working directories..."
    mkdir -p tmp_11_extract tmp_17_extract
    
    echo "[*] Extracting iOS 17.7.11 components..."
    unzip -q -j "$ipsw_17" "Firmware/AOP/aopfw-ipad7baop.RELEASE.im4p" -d tmp_17_extract/
    unzip -q -j "$ipsw_17" "BuildManifest.plist" -d tmp_17_extract/
    
    if [ ! -f "tmp_17_extract/aopfw-ipad7baop.RELEASE.im4p" ]; then
        echo "[#] Error: Could not extract components from iOS 17 IPSW."
        rm -rf tmp_11_extract tmp_17_extract
        exit 1
    fi

    echo "[*] Unzipping iOS 11.3 IPSW structure..."
    unzip -q "$ipsw_11" -d tmp_11_extract/

    echo "[*] Granting write permissions to extracted folders..."
    chmod -R +w tmp_11_extract tmp_17_extract 2>/dev/null

    echo "[*] Overriding iOS 11.3 AOP firmware binary with iOS 17.7.11 version..."
    cp -f tmp_17_extract/aopfw-ipad7baop.RELEASE.im4p tmp_11_extract/Firmware/AOP/aopfw-ipad7baop.im4p

    echo "[*] Writing Python helper to patch BuildManifest.plist hashes..."
    cat << 'EOF' > patch_manifest.py
import sys
import plistlib

manifest11_path = sys.argv[1]
manifest17_path = sys.argv[2]

try:
    with open(manifest11_path, 'rb') as f:
        plist11 = plistlib.load(f)

    with open(manifest17_path, 'rb') as f:
        plist17 = plistlib.load(f)

    aop_17 = None
    for identity in plist17.get('BuildIdentities', []):
        manifest = identity.get('Manifest', {})
        if 'AOP' in manifest:
            aop_17 = manifest['AOP']
            # Make sure it points to the destination filename expected in iOS 11.3
            if 'Info' in aop_17 and 'Path' in aop_17['Info']:
                aop_17['Info']['Path'] = "Firmware/AOP/aopfw-ipad7baop.im4p"
            break

    if not aop_17:
        print("[-] Error: AOP key not found in iOS 17 BuildManifest.")
        sys.exit(1)

    patched_count = 0
    for identity in plist11.get('BuildIdentities', []):
        manifest = identity.get('Manifest', {})
        if 'AOP' in manifest:
            manifest['AOP'] = aop_17
            patched_count += 1

    if patched_count == 0:
        print("[-] Warning: No AOP key found in iOS 11.3 BuildManifest to replace.")
        sys.exit(1)

    with open(manifest11_path, 'wb') as f:
        plistlib.dump(plist11, f)

    print(f"[+] Successfully matched and patched AOP hashes inside {patched_count} build manifest identities.")
except Exception as e:
    print(f"[-] Python error: {e}")
    sys.exit(1)
EOF

    echo "[*] Executing BuildManifest hash injection..."
    python3 patch_manifest.py tmp_11_extract/BuildManifest.plist tmp_17_extract/BuildManifest.plist
    
    if [ $? -ne 0 ]; then
        echo "[#] Error: BuildManifest patch failed. Aborting."
        rm -f patch_manifest.py
        rm -rf tmp_11_extract tmp_17_extract
        exit 1
    fi
    rm -f patch_manifest.py

    echo "[*] Repacking patched iOS 11.3 IPSW (this may take a couple of minutes)..."
    patched_filename="iPad_7,5_11.3_PATCHED.ipsw"
    
    rm -f "../$patched_filename"
    cd tmp_11_extract || exit 1
    zip -q -r "../$patched_filename" .
    cd ..

    echo "[!] Patched IPSW successfully written to: $patched_filename"
    
    # Cleanup working directories
    echo "[*] Cleaning up temporary files..."
    rm -rf tmp_11_extract tmp_17_extract
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
if [ -f "iPad_7,5_11.3_PATCHED.ipsw" ]; then
    echo "Run the restore using your valid SHSH blob and the newly patched IPSW:"
    echo ""
    echo "sudo ./bin/turdus_merula -w --load-shsh $shsh $(pwd)/iPad_7,5_11.3_PATCHED.ipsw"
else
    echo "No patched IPSW was created."
fi
echo "========================================================================="
