#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
outputs_root="$repo_root/outputs/release-packages"
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

deb_field() {
    local deb_path="$1"
    local field_name="$2"

    dpkg-deb -f "$deb_path" "$field_name"
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

build_theos_deb() {
    local flavor="$1"
    local scheme="${2:-}"
    local package_dir="$work_dir/theos-packages-$flavor"
    local deb_path
    local -a make_args=(
        -C "$repo_root"
        FINALPACKAGE=1
        "THEOS_PACKAGE_DIR=$package_dir"
    )

    if [ -n "$scheme" ]; then
        make_args+=("THEOS_PACKAGE_SCHEME=$scheme")
    fi

    rm -rf "$package_dir"
    mkdir -p "$package_dir"

    log "building source deb for $flavor"
    make "${make_args[@]}" clean package >&2

    deb_path="$(find "$package_dir" -maxdepth 1 -type f -name '*.deb' | sort | head -n 1)"
    [ -n "$deb_path" ] || fail "no deb produced for $flavor"

    printf '%s\n' "$deb_path"
}

compose_output_path() {
    local input_deb="$1"
    local flavor="$2"
    local arch="$3"
    local version
    local display_name
    local raw_basename
    local base_prefix

    version="$(deb_field "$input_deb" Version)"
    display_name="$(deb_field "$input_deb" Name | tr -cd '[:alnum:]_.-')"
    raw_basename="$(basename "$input_deb" .deb)"

    if [ -n "$display_name" ]; then
        base_prefix="${display_name}_${version}"
    elif [[ "$raw_basename" == *"_${version}_"* ]]; then
        base_prefix="${raw_basename%%_${version}_*}_${version}"
    else
        base_prefix="$raw_basename"
    fi

    printf '%s/%s/%s_%s_%s.deb\n' "$outputs_root" "$flavor" "$base_prefix" "$flavor" "$arch"
}

set_control_architecture() {
    local control_path="$1"
    local architecture="$2"

    [ -f "$control_path" ] || fail "missing control file: $control_path"
    perl -0pi -e "s/^Architecture:\\s+\\S+\$/Architecture: $architecture/m" "$control_path"
}

repack_stage() {
    local stage_dir="$1"
    local output_path="$2"

    mkdir -p "$(dirname "$output_path")"
    dpkg-deb --root-owner-group -b "$stage_dir" "$output_path" >/dev/null
}

normalize_deb() {
    local input_deb="$1"
    local flavor="$2"
    local architecture="$3"
    local stage_dir="$work_dir/normalize-$flavor"
    local output_path

    rm -rf "$stage_dir"
    dpkg-deb -R "$input_deb" "$stage_dir"

    set_control_architecture "$stage_dir/DEBIAN/control" "$architecture"

    output_path="$(compose_output_path "$input_deb" "$flavor" "$architecture")"
    repack_stage "$stage_dir" "$output_path"

    printf '%s\n' "$output_path"
}

rewrite_rootless_prefixes() {
    local target_path="$1"

    [ -f "$target_path" ] || return 0

    perl -0pi -e '
        s#/var/jb/Applications/#/Applications/#g;
        s#/var/jb/Library/#/Library/#g;
        s#/var/jb/usr/#/usr/#g;
        s#/var/jb/etc/#/etc/#g;
        s#/var/jb/bin/#/bin/#g;
        s#/var/jb/sbin/#/sbin/#g;
        s#/var/jb/System/#/System/#g;
        s#/var/jb/private/#/private/#g;
        s#/var/jb/var/#/var/#g;
    ' "$target_path"
}

rewrite_roothide_text_paths() {
    local stage_dir="$1"
    local script_name
    local plist_path

    for script_name in preinst postinst prerm postrm; do
        rewrite_rootless_prefixes "$stage_dir/DEBIAN/$script_name"
    done

    while IFS= read -r plist_path; do
        rewrite_rootless_prefixes "$plist_path"
    done < <(find "$stage_dir/Library/LaunchDaemons" "$stage_dir/Library/LaunchAgents" -type f -name '*.plist' 2>/dev/null | sort)
}

copy_roothide_macho_files() {
    local roothide_source_dir="$1"
    local target_stage_dir="$2"
    local source_path
    local relative_path
    local target_path
    local file_kind
    local replaced_count=0

    while IFS= read -r source_path; do
        relative_path="${source_path#$roothide_source_dir/}"

        case "$relative_path" in
            DEBIAN/*)
                continue
                ;;
        esac

        target_path="$target_stage_dir/$relative_path"
        [ -f "$target_path" ] || continue

        file_kind="$(file -b "$source_path")"
        if [[ "$file_kind" == *"Mach-O"* ]]; then
            cp -f -p "$source_path" "$target_path"
            replaced_count=$((replaced_count + 1))
        fi
    done < <(find "$roothide_source_dir" -type f | sort)

    [ "$replaced_count" -gt 0 ] || fail "roothide conversion did not replace any Mach-O files"
    printf '%s\n' "$replaced_count"
}

convert_rootless_to_roothide() {
    local rootless_deb="$1"
    local roothide_source_deb="$2"
    local rootless_unpack_dir="$work_dir/rootless-unpack"
    local roothide_source_unpack_dir="$work_dir/roothide-source-unpack"
    local roothide_stage_dir="$work_dir/roothide-stage"
    local top_level_path
    local replaced_count
    local output_path

    rm -rf "$rootless_unpack_dir" "$roothide_source_unpack_dir" "$roothide_stage_dir"

    dpkg-deb -R "$rootless_deb" "$rootless_unpack_dir"
    dpkg-deb -R "$roothide_source_deb" "$roothide_source_unpack_dir"

    [ -d "$rootless_unpack_dir/DEBIAN" ] || fail "rootless package is missing DEBIAN"
    [ -d "$rootless_unpack_dir/var/jb" ] || fail "rootless package is missing var/jb"

    mkdir -p "$roothide_stage_dir"
    mv "$rootless_unpack_dir/DEBIAN" "$roothide_stage_dir/DEBIAN"

    while IFS= read -r top_level_path; do
        mv "$top_level_path" "$roothide_stage_dir/"
    done < <(find "$rootless_unpack_dir/var/jb" -mindepth 1 -maxdepth 1 | sort)

    rm -rf "$rootless_unpack_dir/var"

    if find "$rootless_unpack_dir" -mindepth 1 -maxdepth 1 | grep -q .; then
        mkdir -p "$roothide_stage_dir/rootfs"
        while IFS= read -r top_level_path; do
            mv "$top_level_path" "$roothide_stage_dir/rootfs/"
        done < <(find "$rootless_unpack_dir" -mindepth 1 -maxdepth 1 | sort)
    fi

    replaced_count="$(copy_roothide_macho_files "$roothide_source_unpack_dir" "$roothide_stage_dir")"
    rewrite_roothide_text_paths "$roothide_stage_dir"
    set_control_architecture "$roothide_stage_dir/DEBIAN/control" "iphoneos-arm64e"

    output_path="$(compose_output_path "$roothide_source_deb" "roothide" "iphoneos-arm64e")"
    repack_stage "$roothide_stage_dir" "$output_path"

    log "replaced $replaced_count Mach-O file(s) for roothide"
    printf '%s\n' "$output_path"
}

unpack_for_verification() {
    local deb_path="$1"
    local unpack_dir="$work_dir/verify-$(basename "$deb_path" .deb)"

    rm -rf "$unpack_dir"
    dpkg-deb -R "$deb_path" "$unpack_dir"

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

    otool -L "$binary_path" | grep -Fq "$expected_text" || fail "$(basename "$binary_path") is missing expected load command text: $expected_text"
}

assert_otool_not_contains() {
    local binary_path="$1"
    local unexpected_text="$2"

    if otool -L "$binary_path" | grep -Fq "$unexpected_text"; then
        fail "$(basename "$binary_path") still contains unexpected load command text: $unexpected_text"
    fi
}

binary_contains_text() {
    local binary_path="$1"
    local needle="$2"
    local thin_binary="$work_dir/$(basename "$binary_path").strings.$RANDOM"
    local strings_target="$binary_path"

    if lipo -thin arm64e "$binary_path" -output "$thin_binary" >/dev/null 2>&1; then
        strings_target="$thin_binary"
    elif lipo -thin arm64 "$binary_path" -output "$thin_binary" >/dev/null 2>&1; then
        strings_target="$thin_binary"
    fi

    if strings -a "$strings_target" 2>/dev/null | grep -Fq "$needle"; then
        rm -f "$thin_binary"
        return 0
    fi

    rm -f "$thin_binary"
    return 1
}

assert_binary_contains() {
    local binary_path="$1"
    local expected_text="$2"

    binary_contains_text "$binary_path" "$expected_text" || fail "$(basename "$binary_path") is missing expected binary string: $expected_text"
}

assert_binary_not_contains() {
    local binary_path="$1"
    local unexpected_text="$2"

    if binary_contains_text "$binary_path" "$unexpected_text"; then
        fail "$(basename "$binary_path") still contains unexpected binary string: $unexpected_text"
    fi
}

assert_text_path_absent() {
    local unpack_dir="$1"
    local unexpected_text="$2"

    if grep -R -n -I "$unexpected_text" "$unpack_dir" >/dev/null 2>&1; then
        fail "$(basename "$unpack_dir") still contains unexpected text path: $unexpected_text"
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
    assert_exists "$unpack_dir/Library/MobileSubstrate/DynamicLibraries/NotificationFilter.plist"
    assert_exists "$prefs_binary"
    assert_exists "$unpack_dir/Library/PreferenceLoader/Preferences/NotificationFilterPrefs"
    assert_absent "$unpack_dir/var/jb"
    assert_otool_contains "$prefs_binary" "/Library/PreferenceBundles/NotificationFilterPrefs.bundle/NotificationFilterPrefs"
    assert_binary_not_contains "$tweak_binary" "/var/jb"
    assert_binary_not_contains "$prefs_binary" "/var/jb"
    assert_text_path_absent "$unpack_dir" "/var/jb"
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
    assert_exists "$unpack_dir/var/jb/Library/MobileSubstrate/DynamicLibraries/NotificationFilter.plist"
    assert_exists "$prefs_binary"
    assert_exists "$unpack_dir/var/jb/Library/PreferenceLoader/Preferences/NotificationFilterPrefs"
    assert_absent "$unpack_dir/Library"
    assert_otool_contains "$prefs_binary" "/var/jb/Library/PreferenceBundles/NotificationFilterPrefs.bundle/NotificationFilterPrefs"
    assert_binary_contains "$tweak_binary" "/var/jb"
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
    assert_exists "$unpack_dir/Library/MobileSubstrate/DynamicLibraries/NotificationFilter.plist"
    assert_exists "$prefs_binary"
    assert_exists "$unpack_dir/Library/PreferenceLoader/Preferences/NotificationFilterPrefs"
    assert_absent "$unpack_dir/var/jb"
    assert_otool_contains "$tweak_binary" "@loader_path/.jbroot/Library/MobileSubstrate/DynamicLibraries/NotificationFilter.dylib"
    assert_otool_contains "$tweak_binary" "@loader_path/.jbroot/usr/lib/libsubstrate.dylib"
    assert_otool_contains "$prefs_binary" "/Library/PreferenceBundles/NotificationFilterPrefs.bundle/NotificationFilterPrefs"
    assert_otool_not_contains "$prefs_binary" "/var/jb/Library/PreferenceBundles/NotificationFilterPrefs.bundle/NotificationFilterPrefs"
    assert_binary_not_contains "$tweak_binary" "/var/jb"
    assert_binary_not_contains "$prefs_binary" "/var/jb"
    assert_text_path_absent "$unpack_dir" "/var/jb"
}

main() {
    local rootful_source_deb=""
    local rootless_source_deb=""
    local roothide_source_deb=""
    local rootful_output=""
    local rootless_output=""
    local roothide_output=""

    require_command make
    require_command dpkg-deb
    require_command perl
    require_command otool
    require_command strings
    require_command lipo
    require_command file

    parse_targets "$@"

    mkdir -p "$outputs_root/rootful" "$outputs_root/rootless" "$outputs_root/roothide"

    if [ "$want_rootful" -eq 1 ]; then
        rootful_source_deb="$(build_theos_deb rootful)"
        rootful_output="$(normalize_deb "$rootful_source_deb" "rootful" "iphoneos-arm")"
        verify_rootful_deb "$rootful_output"
    fi

    if [ "$want_rootless" -eq 1 ] || [ "$want_roothide" -eq 1 ]; then
        rootless_source_deb="$(build_theos_deb rootless rootless)"
    fi

    if [ "$want_rootless" -eq 1 ]; then
        rootless_output="$(normalize_deb "$rootless_source_deb" "rootless" "iphoneos-arm64")"
        verify_rootless_deb "$rootless_output"
    fi

    if [ "$want_roothide" -eq 1 ]; then
        roothide_source_deb="$(build_theos_deb roothide-source roothide)"
        roothide_output="$(convert_rootless_to_roothide "$rootless_source_deb" "$roothide_source_deb")"
        verify_roothide_deb "$roothide_output"
    fi

    log "build complete"

    [ -n "$rootful_output" ] && printf '%s\n' "$rootful_output"
    [ -n "$rootless_output" ] && printf '%s\n' "$rootless_output"
    [ -n "$roothide_output" ] && printf '%s\n' "$roothide_output"
}

main "$@"
