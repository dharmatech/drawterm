#!/usr/bin/env bash

set -Eeuo pipefail

usage()
{
	cat <<'EOF'
usage: build-windows-wsl.sh --source PATH --commit SHA --output PATH [--keep-build-tree]

Clone a committed Windows Drawterm checkout into a temporary native-WSL
directory, build a Windows executable with MinGW-w64, inspect it, and copy the
verified artifact to the requested Windows-visible output path.
EOF
}

source_repository=
source_commit=
output_path=
keep_build_tree=0
build_root=

while (($# > 0)); do
	case "$1" in
	--source)
		(($# >= 2)) || { usage >&2; exit 2; }
		source_repository=$2
		shift 2
		;;
	--commit)
		(($# >= 2)) || { usage >&2; exit 2; }
		source_commit=$2
		shift 2
		;;
	--output)
		(($# >= 2)) || { usage >&2; exit 2; }
		output_path=$2
		shift 2
		;;
	--keep-build-tree)
		keep_build_tree=1
		shift
		;;
	-h|--help)
		usage
		exit 0
		;;
	*)
		printf 'unknown argument: %s\n' "$1" >&2
		usage >&2
		exit 2
		;;
	esac
done

if [[ -z "$source_repository" || -z "$source_commit" || -z "$output_path" ]]; then
	usage >&2
	exit 2
fi
if [[ ! "$source_commit" =~ ^[0-9a-fA-F]{40}$ ]]; then
	printf 'invalid source commit: %s\n' "$source_commit" >&2
	exit 2
fi
if [[ ! -d "$source_repository/.git" ]]; then
	printf 'source repository is not a Git checkout: %s\n' "$source_repository" >&2
	exit 2
fi
if [[ ! -d "$(dirname "$output_path")" ]]; then
	printf 'output directory does not exist: %s\n' "$(dirname "$output_path")" >&2
	exit 2
fi
if [[ -e "$output_path" ]]; then
	printf 'refusing to replace existing staging output: %s\n' "$output_path" >&2
	exit 2
fi

missing=()
for command_name in git make file x86_64-w64-mingw32-gcc x86_64-w64-mingw32-objdump; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		missing+=("$command_name")
	fi
done
if ((${#missing[@]} > 0)); then
	printf 'missing required WSL tools: %s\n' "${missing[*]}" >&2
	cat >&2 <<'EOF'

On Ubuntu, install the tested prerequisites with:

    sudo apt update
    sudo apt install git make file gcc-mingw-w64-x86-64 binutils-mingw-w64-x86-64
EOF
	exit 2
fi

cleanup()
{
	status=$?
	trap - EXIT
	if [[ -n "$build_root" && -d "$build_root" ]]; then
		if ((status == 0 && keep_build_tree == 0)); then
			rm -rf -- "$build_root"
			printf 'Removed temporary WSL build tree: %s\n' "$build_root"
		else
			printf 'Preserved WSL build tree: %s\n' "$build_root" >&2
		fi
	fi
	exit "$status"
}
trap cleanup EXIT

build_root=$(mktemp -d "${TMPDIR:-/tmp}/drawterm-build.XXXXXXXX")
checkout="$build_root/drawterm"

printf 'Temporary WSL build tree: %s\n' "$build_root"
printf 'Cloning local Windows repository: %s\n' "$source_repository"
git clone --no-local --no-checkout "$source_repository" "$checkout"
git -C "$checkout" checkout --detach "$source_commit"

checked_out_commit=$(git -C "$checkout" rev-parse HEAD)
if [[ "$checked_out_commit" != "$source_commit" ]]; then
	printf 'checked-out commit mismatch: expected %s, got %s\n' \
		"$source_commit" "$checked_out_commit" >&2
	exit 1
fi
printf 'Building commit: %s\n' "$checked_out_commit"

printf 'Cleaning the temporary checkout\n'
make --no-print-directory -s -C "$checkout" CONF=win64 clean
printf 'Compiling Drawterm with MinGW-w64\n'
make --no-print-directory -s -C "$checkout" CONF=win64

executable="$checkout/drawterm.exe"
if [[ ! -f "$executable" ]]; then
	printf 'build did not produce drawterm.exe\n' >&2
	exit 1
fi

file_description=$(file -b "$executable")
case "$file_description" in
*PE32+*x86-64*)
	;;
*)
	printf 'unexpected executable format: %s\n' "$file_description" >&2
	exit 1
	;;
esac

pe_details=$(x86_64-w64-mingw32-objdump -p "$executable")
subsystem=$(
	printf '%s\n' "$pe_details" |
		awk '$1 == "Subsystem" && !found { value = $2; found = 1 }
		     END { if(found) print value }'
)
if [[ "$subsystem" != "00000003" ]]; then
	printf 'unexpected PE subsystem: %s (expected 00000003, Windows CUI)\n' \
		"${subsystem:-missing}" >&2
	exit 1
fi

dll_names=$(printf '%s\n' "$pe_details" | awk '/DLL Name:/ { print $3 }')
lower_dll_names=$(printf '%s\n' "$dll_names" | tr '[:upper:]' '[:lower:]')
case "$lower_dll_names" in
*cygwin1.dll*|*libgcc_s*|*libstdc++*|*libwinpthread*)
	printf 'unexpected non-system runtime dependency:\n%s\n' "$dll_names" >&2
	exit 1
	;;
esac

printf 'Executable format: %s\n' "$file_description"
printf 'PE subsystem: Windows CUI (3)\n'
printf 'Imported DLLs:\n%s\n' "$dll_names"

cp -- "$executable" "$output_path"
printf 'Copied verified artifact to: %s\n' "$output_path"
