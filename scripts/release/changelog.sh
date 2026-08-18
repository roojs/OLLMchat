#!/usr/bin/env bash
# Generate debian/changelog and RPM %changelog from CHANGELOG.md, and finalize
# releases. CHANGELOG.md is the single source of truth.
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

tag_to_rpm_version() {
  local tag="$1"
  local version="${tag#v}"
  version="${version//-/\~}"
  echo "$version"
}

heading_date_is_iso() {
  [[ "${1:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

normalize_entry_date() {
  local date="${1:-}"
  if heading_date_is_iso "$date"; then
    echo "$date"
  else
    date -u '+%Y-%m-%d'
  fi
}

debian_date() {
  date -u -d "$(normalize_entry_date "${1:-}")" '+%a, %d %b %Y %H:%M:%S +0000'
}

rpm_date() {
  date -u -d "$(normalize_entry_date "${1:-}")" '+%a %b %d %Y'
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
  local in_fence=0

  rm -rf "$outdir"
  mkdir -p "$outdir"

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^\`\`\` ]]; then
      in_fence=$((1 - in_fence))
      if (( section >= 0 )); then
        printf '%s\n' "$line" >> "$body_file"
      fi
      continue
    fi
    if (( in_fence )) && (( section < 0 )); then
      continue
    fi
    if [[ "$line" =~ ^##\ \[([^]]+)\](\ -\ (Unreleased|[0-9]{4}-[0-9]{2}-[0-9]{2}))?[[:space:]]*$ ]]; then
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
  local tmpdir last index title date

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

render_rpm_changelog() {
  local tmpdir last index title date bullet rpm_ver

  tmpdir="$(mktemp -d)"
  last="$(parse_sections_to_dir "$CHANGELOG_MD" "$tmpdir")"

  printf '%s\n' '%changelog'
  for ((index = 0; index <= last; index++)); do
    title="$(<"$tmpdir/$index.title")"
    [[ "$title" == "Unreleased" ]] && continue
    date="$(<"$tmpdir/$index.date")"
    rpm_ver="$(tag_to_rpm_version "$title")"
    printf '\n* %s %s - %s-1\n' "$(rpm_date "$date")" "$MAINTAINER" "$rpm_ver"
    mapfile -t bullets < <(extract_bullets < "$tmpdir/$index.body")
    if ((${#bullets[@]} == 0)); then
      printf -- '- Release %s\n' "$title"
      continue
    fi
    for bullet in "${bullets[@]}"; do
      printf -- '- %s\n' "$bullet"
    done
  done

  rm -rf "$tmpdir"
}

splice_rpm_spec() {
  local spec="$1"
  local tmp_spec

  [[ -f "$spec" ]] || die "spec not found: $spec"
  tmp_spec="$(mktemp)"
  awk 'BEGIN { p = 1 } /^%changelog/ { p = 0 } p { print }' "$spec" > "$tmp_spec"
  render_rpm_changelog >> "$tmp_spec"
  mv "$tmp_spec" "$spec"
}

cmd_sync() {
  local release_tag=""
  local splice_spec=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --release)
        [[ $# -ge 2 ]] || die "sync --release requires a tag argument"
        release_tag="$2"
        shift 2
        ;;
      --splice-spec)
        [[ $# -ge 2 ]] || die "sync --splice-spec requires a spec path"
        splice_spec="$2"
        shift 2
        ;;
      *)
        die "Unknown sync argument: $1"
        ;;
    esac
  done

  write_debian_changelog "$release_tag"
  echo "Wrote debian/changelog"
  if [[ -n "$splice_spec" ]]; then
    splice_rpm_spec "$splice_spec"
    echo "Spliced RPM %changelog into ${splice_spec}"
  fi
}

cmd_version() {
  local tmpdir last title date

  tmpdir="$(mktemp -d)"
  last="$(parse_sections_to_dir "$CHANGELOG_MD" "$tmpdir")"
  title="$(<"$tmpdir/0.title")"
  date="$(<"$tmpdir/0.date")"
  rm -rf "$tmpdir"

  if [[ "$title" == "Unreleased" ]]; then
    die "CHANGELOG.md: set the version in the first heading (## [X.Y.Z] - Unreleased) before releasing"
  fi
  if heading_date_is_iso "$date"; then
    die "CHANGELOG.md: first section [${title}] is already dated ${date}; add ## [next] - Unreleased"
  fi
  printf '%s\n' "$title"
}

cmd_packaging_version() {
  local tmpdir last index title

  tmpdir="$(mktemp -d)"
  last="$(parse_sections_to_dir "$CHANGELOG_MD" "$tmpdir")"
  for ((index = 0; index <= last; index++)); do
    title="$(<"$tmpdir/$index.title")"
    if [[ "$title" != "Unreleased" ]]; then
      rm -rf "$tmpdir"
      printf '%s\n' "$title"
      return 0
    fi
  done
  rm -rf "$tmpdir"
  die "CHANGELOG.md: no versioned section found"
}

cmd_notes() {
  local tmpdir last title body

  tmpdir="$(mktemp -d)"
  last="$(parse_sections_to_dir "$CHANGELOG_MD" "$tmpdir")"
  title="$(<"$tmpdir/0.title")"
  body="$(trim_section_body < "$tmpdir/0.body")"
  rm -rf "$tmpdir"

  if [[ -z "$body" ]]; then
    die "CHANGELOG.md: empty notes for [${title}]"
  fi
  printf '%s\n' "$body"
}

extract_unreleased_body() {
  awk '
    /^## \[Unreleased\][[:space:]]*$/ {
      in_section = 1
      next
    }
    /^## \[[^]]+\] - Unreleased[[:space:]]*$/ {
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
  local body version tmpdir last index title

  [[ -n "$tag" ]] || die "release-notes requires a tag"
  version="${tag#v}"

  tmpdir="$(mktemp -d)"
  last="$(parse_sections_to_dir "$CHANGELOG_MD" "$tmpdir")"
  if index="$(find_section_index "$tmpdir" "$version" "$last")"; then
    body="$(trim_section_body < "$tmpdir/$index.body")"
  else
    body="$(extract_unreleased_body)"
  fi
  rm -rf "$tmpdir"

  if [[ -z "$body" ]]; then
    die "CHANGELOG.md: no notes for ${tag}"
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

  if grep -qE "^## \[${version}\] - [0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]*$" "$CHANGELOG_MD"; then
    die "CHANGELOG.md already contains dated [${version}]"
  fi

  today="$(date -u '+%Y-%m-%d')"
  tmp="$(mktemp)"

  if grep -qE "^## \[${version}\] - Unreleased[[:space:]]*$" "$CHANGELOG_MD"; then
    awk -v version="$version" -v today="$today" '
      BEGIN { inserted = 0 }
      /^## \[/ && !inserted {
        if ($0 !~ /^## \[Unreleased\][[:space:]]*$/) {
          print "## [Unreleased]"
          print ""
        }
        inserted = 1
      }
      $0 ~ ("^## \\[" version "\\] - Unreleased[[:space:]]*$") {
        print "## [" version "] - " today
        next
      }
      { print }
    ' "$CHANGELOG_MD" > "$tmp"
    mv "$tmp" "$CHANGELOG_MD"
    write_debian_changelog ""
    echo "Finalized ${version} in CHANGELOG.md"
    return
  fi

  unreleased_body="$(extract_unreleased_body)"
  if [[ -z "$unreleased_body" ]]; then
    die "CHANGELOG.md: missing [Unreleased] section"
  fi

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
  $(basename "$0") version
  $(basename "$0") packaging-version
  $(basename "$0") notes
  $(basename "$0") sync [--release TAG] [--splice-spec SPEC]
  $(basename "$0") finalize TAG
  $(basename "$0") release-notes TAG [-o OUTPUT]

Generate debian/changelog and RPM %changelog from CHANGELOG.md and finalize
releases. Before tagging, set the first heading to ## [X.Y.Z] - Unreleased.
EOF
}

main() {
  [[ $# -ge 1 ]] || {
    usage >&2
    exit 1
  }

  case "$1" in
    version)
      cmd_version
      ;;
    packaging-version)
      cmd_packaging_version
      ;;
    notes)
      cmd_notes
      ;;
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
