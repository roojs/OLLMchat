#!/usr/bin/env bash
# Generate debian/changelog from CHANGELOG.md and finalize releases.
set -euo pipefail

MAINTAINER='Alan Knowles <alan@roojs.com>'
PACKAGE='ollmchat'
DISTRIBUTION='unstable'
URGENCY='medium'

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHANGELOG_MD="$ROOT/CHANGELOG.md"
DEBIAN_CHANGELOG="$ROOT/debian/changelog"

die() {
  echo "$*" >&2
  exit 1
}

tag_to_debian_version() {
  local tag="$1"
  local version="${tag#v}"
  version="${version//-/\~}"
  echo "${version}-1"
}

debian_date() {
  local iso_date="${1:-}"
  if [[ -n "$iso_date" ]]; then
    date -u -d "${iso_date}" '+%a, %d %b %Y %H:%M:%S +0000'
  else
    date -u '+%a, %d %b %Y %H:%M:%S +0000'
  fi
}

trim_section_body() {
  awk '
    { lines[++n] = $0 }
    END {
      start = 1
      end = n
      while (start <= end && lines[start] ~ /^[[:space:]]*$/) {
        start++
      }
      while (end >= start && lines[end] ~ /^[[:space:]]*$/) {
        end--
      }
      for (i = start; i <= end; i++) {
        print lines[i]
      }
    }
  '
}

extract_bullets() {
  trim_section_body | awk '
    function trim(s) {
      sub(/^[ \t\r]+/, "", s)
      sub(/[ \t\r]+$/, "", s)
      return s
    }
    {
      line = $0
      stripped = trim(line)
      if (stripped == "" || substr(stripped, 1, 1) == "#") {
        next
      }
      if (substr(stripped, 1, 2) == "- " || substr(stripped, 1, 2) == "* ") {
        if (current != "") {
          print current
        }
        current = trim(substr(stripped, 3))
      } else if (current != "" && (substr(line, 1, 2) == "  " || substr(line, 1, 1) == "\t")) {
        current = current " " stripped
      }
    }
    END {
      if (current != "") {
        print current
      }
    }
  '
}

parse_sections_to_dir() {
  local changelog="$1"
  local outdir="$2"
  local section=-1
  local body_file=""

  rm -rf "$outdir"
  mkdir -p "$outdir"

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^##\ \[([^]]+)\](\ -\ ([0-9]{4}-[0-9]{2}-[0-9]{2}))?[[:space:]]*$ ]]; then
      section=$((section + 1))
      printf '%s\n' "${BASH_REMATCH[1]}" > "$outdir/$section.title"
      printf '%s\n' "${BASH_REMATCH[3]:-}" > "$outdir/$section.date"
      body_file="$outdir/$section.body"
      : > "$body_file"
    elif (( section >= 0 )); then
      printf '%s\n' "$line" >> "$body_file"
    fi
  done < "$changelog"

  if (( section < 0 )); then
    die "CHANGELOG.md: no ## [version] sections found"
  fi

  echo "$section"
}

find_section_index() {
  local outdir="$1"
  local want="$2"
  local last="$3"
  local index title

  for ((index = 0; index <= last; index++)); do
    title="$(<"$outdir/$index.title")"
    if [[ "$title" == "$want" ]]; then
      echo "$index"
      return 0
    fi
  done
  return 1
}

render_debian_entry() {
  local title="$1"
  local date="$2"
  local body_file="$3"
  local deb_version bullet

  if [[ "$title" == "Unreleased" ]]; then
    deb_version='UNRELEASED'
  else
    deb_version="$(tag_to_debian_version "$title")"
  fi

  mapfile -t bullets < <(extract_bullets < "$body_file")
  if ((${#bullets[@]} == 0)); then
    bullets=("Release ${title}")
  fi

  printf '%s (%s) %s; urgency=%s\n\n' "$PACKAGE" "$deb_version" "$DISTRIBUTION" "$URGENCY"
  for bullet in "${bullets[@]}"; do
    printf '  * %s\n' "$bullet"
  done
  printf '\n -- %s  %s\n\n' "$MAINTAINER" "$(debian_date "$date")"
}

render_debian_changelog() {
  local release_tag="${1:-}"
  local tmpdir last index title date body_file

  tmpdir="$(mktemp -d)"
  last="$(parse_sections_to_dir "$CHANGELOG_MD" "$tmpdir")"

  if [[ -n "$release_tag" ]]; then
    index="$(find_section_index "$tmpdir" "Unreleased" "$last")" \
      || die "CHANGELOG.md: missing [Unreleased] section"

    title="$release_tag"
    date="$(date -u '+%Y-%m-%d')"
    render_debian_entry "$title" "$date" "$tmpdir/$index.body"

    for ((index = 0; index <= last; index++)); do
      title="$(<"$tmpdir/$index.title")"
      [[ "$title" == "Unreleased" ]] && continue
      date="$(<"$tmpdir/$index.date")"
      render_debian_entry "$title" "$date" "$tmpdir/$index.body"
    done
  else
    for ((index = 0; index <= last; index++)); do
      title="$(<"$tmpdir/$index.title")"
      date="$(<"$tmpdir/$index.date")"
      render_debian_entry "$title" "$date" "$tmpdir/$index.body"
    done
  fi

  rm -rf "$tmpdir"
}

write_debian_changelog() {
  local release_tag="${1:-}"
  mkdir -p "$(dirname "$DEBIAN_CHANGELOG")"
  render_debian_changelog "$release_tag" | sed -e :a -e '/^\n*$/d;N;ba' -e '$!ba' -e 's/\n$//' > "$DEBIAN_CHANGELOG"
  printf '\n' >> "$DEBIAN_CHANGELOG"
}

cmd_sync() {
  local release_tag=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --release)
        [[ $# -ge 2 ]] || die "sync --release requires a tag argument"
        release_tag="$2"
        shift 2
        ;;
      *)
        die "Unknown sync argument: $1"
        ;;
    esac
  done

  write_debian_changelog "$release_tag"
  echo "Wrote debian/changelog"
}

extract_unreleased_body() {
  awk '
    /^## \[Unreleased\][[:space:]]*$/ {
      in_section = 1
      next
    }
    in_section && /^## \[/ {
      exit
    }
    in_section {
      print
    }
  ' "$CHANGELOG_MD" | trim_section_body
}

cmd_release_notes() {
  local tag="$1"
  local output="$2"
  local body

  [[ -n "$tag" ]] || die "release-notes requires a tag"

  body="$(extract_unreleased_body)"
  if [[ -z "$body" ]]; then
    die "CHANGELOG.md: [Unreleased] section is empty"
  fi

  mkdir -p "$(dirname "$output")"
  printf '%s\n' "$body" > "$output"
  if [[ "$output" == "$ROOT/"* ]]; then
    echo "Wrote ${output#"$ROOT"/}"
  else
    echo "Wrote $output"
  fi
}

cmd_finalize() {
  local tag="$1"
  local version="${tag#v}"
  local today unreleased_body replacement tmp

  [[ -n "$tag" ]] || die "finalize requires a tag"

  if grep -qF "## [${version}]" "$CHANGELOG_MD"; then
    die "CHANGELOG.md already contains [${version}]"
  fi

  unreleased_body="$(extract_unreleased_body)"
  if [[ -z "$unreleased_body" ]]; then
    die "CHANGELOG.md: missing [Unreleased] section"
  fi

  today="$(date -u '+%Y-%m-%d')"
  tmp="$(mktemp)"
  replacement="$(mktemp)"

  {
    printf '## [%s] - %s\n\n' "$version" "$today"
    printf '%s\n\n' "$unreleased_body"
    printf '## [Unreleased]\n\n'
  } > "$replacement"

  awk -v rep_file="$replacement" '
    BEGIN {
      while ((getline line < rep_file) > 0) {
        replacement = replacement line "\n"
      }
      close(rep_file)
    }
    /^## \[Unreleased\][[:space:]]*$/ {
      if (!replaced) {
        printf "%s", replacement
        replaced = 1
        in_unreleased = 1
        next
      }
    }
    in_unreleased {
      if (/^## \[/) {
        in_unreleased = 0
        print
      }
      next
    }
    { print }
    END {
      if (!replaced) {
        exit 1
      }
    }
  ' "$CHANGELOG_MD" > "$tmp" || die "CHANGELOG.md: could not replace [Unreleased] section"

  mv "$tmp" "$CHANGELOG_MD"
  rm -f "$replacement"
  write_debian_changelog ""
  echo "Finalized ${version} in CHANGELOG.md"
}

usage() {
  cat <<EOF
Usage:
  $(basename "$0") sync [--release TAG]
  $(basename "$0") finalize TAG
  $(basename "$0") release-notes TAG [-o OUTPUT]

Generate debian/changelog from CHANGELOG.md and finalize releases.
EOF
}

main() {
  [[ $# -ge 1 ]] || {
    usage >&2
    exit 1
  }

  case "$1" in
    sync)
      shift
      cmd_sync "$@"
      ;;
    finalize)
      [[ $# -ge 2 ]] || die "Usage: $(basename "$0") finalize TAG"
      cmd_finalize "$2"
      ;;
    release-notes)
      [[ $# -ge 2 ]] || die "Usage: $(basename "$0") release-notes TAG [-o OUTPUT]"
      local tag="$2"
      local output="$ROOT/release-notes.md"
      shift 2
      while [[ $# -gt 0 ]]; do
        case "$1" in
          -o|--output)
            [[ $# -ge 2 ]] || die "release-notes -o requires a path"
            output="$2"
            shift 2
            ;;
          *)
            die "Unknown release-notes argument: $1"
            ;;
        esac
      done
      cmd_release_notes "$tag" "$output"
      ;;
    -h|--help)
      usage
      ;;
    *)
      die "Unknown command: $1"
      ;;
  esac
}

main "$@"
