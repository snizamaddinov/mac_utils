#!/bin/zsh
set -euo pipefail

project_directory="${0:A:h}"
installation_directory="${HOME}/Applications"
application_bundle="${installation_directory}/InputChanger.app"
legacy_application_bundle="${installation_directory}/Input Changer.app"
executable_directory="${application_bundle}/Contents/MacOS"
swift_module_map="/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap"
swift_module_map_backup="/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap.stale"

if [[ -f "${swift_module_map}" ]]; then
    print "Removing the stale SwiftBridging module map requires administrator access."
    if [[ -e "${swift_module_map_backup}" ]]; then
        swift_module_map_backup="${swift_module_map_backup}.$(/bin/date +%Y%m%d%H%M%S)"
    fi
    /usr/bin/sudo /bin/mv "${swift_module_map}" "${swift_module_map_backup}"
fi

if /usr/bin/pgrep -x InputChanger >/dev/null 2>&1; then
    print "Quit InputChanger before installing this update."
    exit 1
fi

if [[ -d "${legacy_application_bundle}" && ! -e "${application_bundle}" ]]; then
    /bin/mv "${legacy_application_bundle}" "${application_bundle}"
fi

/bin/mkdir -p "${executable_directory}"
/usr/bin/xcrun swiftc "${project_directory}/main.swift" -O -framework AppKit -framework Carbon -framework ServiceManagement -o "${executable_directory}/InputChanger"
/bin/cp "${project_directory}/Info.plist" "${application_bundle}/Contents/Info.plist"
/usr/bin/codesign --force --sign - "${application_bundle}"
/usr/bin/open "${application_bundle}"

print "Installed ${application_bundle}"
print "You can now open InputChanger from Spotlight."
