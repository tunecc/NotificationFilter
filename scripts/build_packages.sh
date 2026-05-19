#!/opt/homebrew/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
out_root="$repo_root/out"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/notificationfilter-packages.XXXXXX")"

trap 'rm -rf "$work_dir"' EXIT

log() {
    printf '[build_packages] %s\n' "$*" >&2
}

fail() {
    printf '[build_packages] ERROR: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"
}

sanitize_filename_component() {
    printf '%s' "$1" | LC_ALL=C tr -cd 'A-Za-z0-9._+~-'
}

deb_field() {
    local deb_path="$1"
    local field_name="$2"
    dpkg-deb -f "$deb_path" "$field_name"
}

expected_arch_for_flavor() {
    case "$1" in
        rootful) printf '%s\n' "iphoneos-arm" ;;
        rootless) printf '%s\n' "iphoneos-arm64" ;;
        roothide) printf '%s\n' "iphoneos-arm64e" ;;
        *) fail "unknown flavor: $1" ;;
    esac
}

short_arch_for_flavor() {
    case "$1" in
        rootful) printf '%s\n' "arm" ;;
        rootless) printf '%s\n' "arm64" ;;
        roothide) printf '%s\n' "arm64e" ;;
        *) fail "unknown flavor: $1" ;;
    esac
}

scheme_for_flavor() {
    case "$1" in
        rootful) printf '%s\n' "" ;;
        rootless) printf '%s\n' "rootless" ;;
        roothide) printf '%s\n' "roothide" ;;
        *) fail "unknown flavor: $1" ;;
    esac
}

parse_targets() {
    want_rootful=0
    want_rootless=0
    want_roothide=0

    if [ "$#" -eq 0 ]; then
        want_rootful=1
        want_rootless=1
        want_roothide=1
        return 0
    fi

    local target
    for target in "$@"; do
        case "$target" in
            all)
                want_rootful=1
                want_rootless=1
                want_roothide=1
                ;;
            default|release)
                want_rootless=1
                want_roothide=1
                ;;
            rootful)
                want_rootful=1
                ;;
            rootless)
                want_rootless=1
                ;;
            roothide)
                want_roothide=1
                ;;
            *)
                fail "unknown build target: $target"
                ;;
        esac
    done
}

run_make_target() {
    local target="$1"
    shift

    local -a cmd=(make -C "$repo_root" "$target")
    local arg
    local cmdline=""

    for arg in "$@"; do
        cmd+=("$arg")
    done

    for arg in "${cmd[@]}"; do
        printf -v cmdline '%s%q ' "$cmdline" "$arg"
    done

    env -i \
        PATH="$PATH" \
        HOME="$HOME" \
        THEOS="${THEOS:-}" \
        TMPDIR="${TMPDIR:-/tmp}" \
        /bin/bash -lc "$cmdline" >&2
}

remove_path_with_retry() {
    local target_path="$1"
    local attempt

    for attempt in 1 2 3; do
        [ ! -e "$target_path" ] && return 0
        rm -rf "$target_path" 2>/dev/null && return 0
        sleep "$attempt"
    done

    rm -rf "$target_path"
}

clean_host_metadata() {
    local target_path

    for target_path in "$@"; do
        [ -e "$target_path" ] || continue
        find "$target_path" -type f -name '.DS_Store' -delete
        find "$target_path" -type f -name '._*' -delete
        find "$target_path" -name '__MACOSX' -type d -prune -exec rm -rf {} +
    done
}

clean_intermediate_build_state() {
    if [ -d "$repo_root/.theos" ]; then
        find "$repo_root/.theos" -mindepth 1 -maxdepth 1 -print0 | while IFS= read -r -d '' entry; do
            remove_path_with_retry "$entry"
        done
    fi
    remove_path_with_retry "$repo_root/_"
}

run_make_clean_with_retry() {
    local flavor="$1"
    shift
    local attempt

    for attempt in 1 2 3; do
        if run_make_target clean "$@"; then
            return 0
        fi
        log "clean failed for $flavor, retrying after clearing intermediate state (attempt $attempt)"
        clean_intermediate_build_state
        sleep "$attempt"
    done

    fail "clean failed for $flavor after retries"
}

native_build_workaround_vars() {
    local scheme="$1"
    local sdk_root="/Applications/Xcode-14.2.0.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS16.2.sdk"

    if [ -d "$sdk_root" ]; then
        printf '%s\n' "SYSROOT=$sdk_root"
        printf '%s\n' "ISYSROOT=$sdk_root"
        printf '%s\n' "MODULESFLAGS="
        printf '%s\n' "NotificationFilter_USE_MODULES=0"
        printf '%s\n' "NotificationFilterPrefs_USE_MODULES=0"
        printf '%s\n' "NotificationFilter_CFLAGS=-fobjc-arc"
        printf '%s\n' "NotificationFilterPrefs_CFLAGS=-fobjc-arc -Wno-error=deprecated-declarations"
    fi

    if [ "$scheme" = "roothide" ]; then
        printf '%s\n' "NotificationFilter_LIBRARIES=roothide"
        printf '%s\n' "NotificationFilterPrefs_LIBRARIES=roothide"
    else
        printf '%s\n' "NotificationFilter_LIBRARIES="
        printf '%s\n' "NotificationFilterPrefs_LIBRARIES="
    fi
}

build_native_deb() {
    local flavor="$1"
    local scheme
    local package_dir="$work_dir/packages-$flavor"
    local deb_path=""
    local -a make_vars=(
        "FINALPACKAGE=1"
        "THEOS_PACKAGE_DIR=$package_dir"
    )
    local workaround_var

    scheme="$(scheme_for_flavor "$flavor")"
    make_vars+=("THEOS_PACKAGE_SCHEME=$scheme")

    while IFS= read -r workaround_var; do
        [ -n "$workaround_var" ] || continue
        make_vars+=("$workaround_var")
    done < <(native_build_workaround_vars "$scheme")

    remove_path_with_retry "$package_dir"
    mkdir -p "$package_dir"

    log "building native $flavor package"
    run_make_clean_with_retry "$flavor" "${make_vars[@]}"
    clean_host_metadata "$repo_root" "$package_dir"
    run_make_target package "${make_vars[@]}"
    clean_host_metadata "$package_dir"

    local -a deb_candidates=()
    local deb_candidate
    while IFS= read -r deb_candidate; do
        [ -n "$deb_candidate" ] || continue
        deb_candidates+=("$deb_candidate")
    done < <(find "$package_dir" -maxdepth 1 -type f -name '*.deb' | sort)
    [ "${#deb_candidates[@]}" -gt 0 ] || fail "no deb produced for $flavor"
    [ "${#deb_candidates[@]}" -eq 1 ] || fail "expected exactly one deb for $flavor, got ${#deb_candidates[@]}"

    deb_path="${deb_candidates[0]}"
    printf '%s\n' "$deb_path"
}

expected_output_path() {
    local deb_path="$1"
    local flavor="$2"
    local display_name
    local version
    local short_arch

    display_name="$(deb_field "$deb_path" Name 2>/dev/null || true)"
    if [ -z "$display_name" ]; then
        display_name="$(deb_field "$deb_path" Package)"
    fi
    version="$(deb_field "$deb_path" Version)"
    short_arch="$(short_arch_for_flavor "$flavor")"

    display_name="$(sanitize_filename_component "$display_name")"
    version="$(sanitize_filename_component "$version")"
    [ -n "$display_name" ] || fail "empty display name for $(basename "$deb_path")"
    [ -n "$version" ] || fail "empty version for $(basename "$deb_path")"

    printf '%s/%s_%s_%s_%s.deb\n' "$out_root" "$display_name" "$version" "$flavor" "$short_arch"
}

copy_to_out() {
    local deb_path="$1"
    local flavor="$2"
    local out_path

    out_path="$(expected_output_path "$deb_path" "$flavor")"
    mkdir -p "$out_root"
    find "$out_root" -maxdepth 1 -type f -name "*_${flavor}_*.deb" -delete
    cp -f "$deb_path" "$out_path"
    printf '%s\n' "$out_path"
}

unpack_for_verification() {
    local deb_path="$1"
    local unpack_dir="$work_dir/unpack-$(basename "$deb_path" .deb)"

    rm -rf "$unpack_dir"
    dpkg-deb -R "$deb_path" "$unpack_dir" >/dev/null
    printf '%s\n' "$unpack_dir"
}

assert_architecture() {
    local deb_path="$1"
    local expected_arch="$2"
    local actual_arch

    actual_arch="$(deb_field "$deb_path" Architecture)"
    [ "$actual_arch" = "$expected_arch" ] || fail "$(basename "$deb_path") has unexpected architecture: $actual_arch"
}

assert_exists() {
    local target_path="$1"
    [ -e "$target_path" ] || fail "missing path: $target_path"
}

assert_absent() {
    local target_path="$1"
    [ ! -e "$target_path" ] || fail "unexpected path: $target_path"
}

assert_otool_contains() {
    local binary_path="$1"
    local expected_text="$2"
    otool -L "$binary_path" | grep -Fq "$expected_text" || fail "$(basename "$binary_path") is missing expected load path: $expected_text"
}

assert_clean_unpack_dir() {
    local unpack_dir="$1"
    if find "$unpack_dir" \( -name '.DS_Store' -o -name '._*' -o -name '__MACOSX' \) -print -quit | grep -q .; then
        fail "$(basename "$unpack_dir") contains host metadata files"
    fi
}

verify_rootful_deb() {
    local deb_path="$1"
    local unpack_dir
    local tweak_binary
    local prefs_binary

    unpack_dir="$(unpack_for_verification "$deb_path")"
    tweak_binary="$unpack_dir/Library/MobileSubstrate/DynamicLibraries/NotificationFilter.dylib"
    prefs_binary="$unpack_dir/Library/PreferenceBundles/NotificationFilterPrefs.bundle/NotificationFilterPrefs"

    assert_architecture "$deb_path" "iphoneos-arm"
    assert_exists "$tweak_binary"
    assert_exists "$prefs_binary"
    assert_absent "$unpack_dir/var/jb"
    assert_clean_unpack_dir "$unpack_dir"
}

verify_rootless_deb() {
    local deb_path="$1"
    local unpack_dir
    local tweak_binary
    local prefs_binary

    unpack_dir="$(unpack_for_verification "$deb_path")"
    tweak_binary="$unpack_dir/var/jb/Library/MobileSubstrate/DynamicLibraries/NotificationFilter.dylib"
    prefs_binary="$unpack_dir/var/jb/Library/PreferenceBundles/NotificationFilterPrefs.bundle/NotificationFilterPrefs"

    assert_architecture "$deb_path" "iphoneos-arm64"
    assert_exists "$tweak_binary"
    assert_exists "$prefs_binary"
    assert_absent "$unpack_dir/Library/MobileSubstrate/DynamicLibraries/NotificationFilter.dylib"
    assert_clean_unpack_dir "$unpack_dir"
}

verify_roothide_deb() {
    local deb_path="$1"
    local unpack_dir
    local tweak_binary
    local prefs_binary

    unpack_dir="$(unpack_for_verification "$deb_path")"
    tweak_binary="$unpack_dir/Library/MobileSubstrate/DynamicLibraries/NotificationFilter.dylib"
    prefs_binary="$unpack_dir/Library/PreferenceBundles/NotificationFilterPrefs.bundle/NotificationFilterPrefs"

    assert_architecture "$deb_path" "iphoneos-arm64e"
    assert_exists "$tweak_binary"
    assert_exists "$prefs_binary"
    assert_absent "$unpack_dir/var/jb"
    assert_otool_contains "$tweak_binary" ".jbroot"
    assert_otool_contains "$tweak_binary" "libroothide"
    assert_clean_unpack_dir "$unpack_dir"
}

verify_out_header() {
    local deb_path="$1"
    local flavor="$2"
    local expected_arch
    local actual_package
    local actual_version
    local actual_arch
    local expected_path

    expected_arch="$(expected_arch_for_flavor "$flavor")"
    actual_package="$(deb_field "$deb_path" Package)"
    actual_version="$(deb_field "$deb_path" Version)"
    actual_arch="$(deb_field "$deb_path" Architecture)"
    expected_path="$(expected_output_path "$deb_path" "$flavor")"

    [ "$actual_arch" = "$expected_arch" ] || fail "$(basename "$deb_path") has unexpected architecture: $actual_arch"
    [ "$deb_path" = "$expected_path" ] || fail "$(basename "$deb_path") does not match expected output path: $expected_path"
    [ -n "$actual_package" ] || fail "$(basename "$deb_path") has empty Package field"
    [ -n "$actual_version" ] || fail "$(basename "$deb_path") has empty Version field"

    log "verified $(basename "$deb_path"): $actual_package $actual_version $actual_arch"
}

main() {
    local rootful_source=""
    local rootless_source=""
    local roothide_source=""
    local rootful_out=""
    local rootless_out=""
    local roothide_out=""

    require_command make
    require_command dpkg-deb
    require_command otool
    require_command cp
    require_command find

    parse_targets "$@"

    mkdir -p "$out_root"
    clean_host_metadata "$repo_root"

    if [ "$want_rootful" -eq 1 ]; then
        rootful_source="$(build_native_deb rootful)"
        rootful_out="$(copy_to_out "$rootful_source" rootful)"
        verify_rootful_deb "$rootful_out"
        verify_out_header "$rootful_out" rootful
    fi

    if [ "$want_rootless" -eq 1 ]; then
        rootless_source="$(build_native_deb rootless)"
        rootless_out="$(copy_to_out "$rootless_source" rootless)"
        verify_rootless_deb "$rootless_out"
        verify_out_header "$rootless_out" rootless
    fi

    if [ "$want_roothide" -eq 1 ]; then
        roothide_source="$(build_native_deb roothide)"
        roothide_out="$(copy_to_out "$roothide_source" roothide)"
        verify_roothide_deb "$roothide_out"
        verify_out_header "$roothide_out" roothide
    fi

    log "build complete"
    [ -n "$rootful_out" ] && printf '%s\n' "$rootful_out"
    [ -n "$rootless_out" ] && printf '%s\n' "$rootless_out"
    [ -n "$roothide_out" ] && printf '%s\n' "$roothide_out"
    return 0
}

main "$@"
