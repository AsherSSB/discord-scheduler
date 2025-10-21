#!/usr/bin/env bash
set -euo pipefail

os_name="$(uname -s)"
distro_id=""
if [ "$os_name" = "Linux" ] && [ -r /etc/os-release ]; then
  . /etc/os-release || true
  distro_id="${ID:-}"
fi

have() { command -v "$1" >/dev/null 2>&1; }

python_ok() {
  local py version major
  if have python3; then py=python3
  elif have python; then py=python
  else return 1
  fi
  version="$($py -V 2>&1 | awk '{print $2}')"
  major="${version%%.*}"
  [ "${major:-0}" -ge 3 ]
}

find_godot() {
  local c
  for c in "${GODOT_BIN:-}" godot godot4 godot-headless godot4-headless; do
    [ -n "$c" ] && have "$c" && { echo "$c"; return 0; }
  done
  return 1
}

missing=()
have rsync || missing+=("rsync")
have curl  || missing+=("curl")
have npm   || missing+=("npm")
python_ok  || missing+=("python3")
find_godot >/dev/null || missing+=("godot")

map_pkg() {
  local tool="$1"
  case "$os_name" in
    Darwin)
      case "$tool" in
        python3) echo "python" ;;
        npm)     echo "node" ;;
        godot)   echo "godot" ;;
        *)       echo "$tool" ;;
      esac
      ;;
    Linux)
      case "$distro_id" in
        arch)
          case "$tool" in
            python3) echo "python" ;;
            npm)     echo "npm nodejs" ;;
            godot)   echo "godot" ;;
            *)       echo "$tool" ;;
          esac
          ;;
        debian|ubuntu)
          case "$tool" in
            python3) echo "python3" ;;
            npm)     echo "npm nodejs" ;;
            godot)   echo "godot4" ;;
            *)       echo "$tool" ;;
          esac
          ;;
        fedora)
          case "$tool" in
            python3) echo "python3" ;;
            npm)     echo "npm nodejs" ;;
            godot)   echo "godot" ;;
            *)       echo "$tool" ;;
          esac
          ;;
        opensuse*|sled|sles)
          case "$tool" in
            python3) echo "python3" ;;
            npm)     echo "npm nodejs" ;;
            godot)   echo "godot4" ;;
            *)       echo "$tool" ;;
          esac
          ;;
        alpine)
          case "$tool" in
            python3) echo "python3" ;;
            npm)     echo "npm nodejs" ;;
            godot)   echo "godot" ;;
            *)       echo "$tool" ;;
          esac
          ;;
        *)
          echo "$tool"
          ;;
      esac
      ;;
    *)
      echo "$tool"
      ;;
  esac
}

install_hint() {
  [ "${#missing[@]}" -gt 0 ] || return 0

  case "$os_name" in
    Darwin)
      local formulae=() casks=() t names
      for t in "${missing[@]}"; do
        names=($(map_pkg "$t"))
        for n in "${names[@]}"; do
          if [ "$n" = "godot" ]; then casks+=("$n"); else formulae+=("$n"); fi
        done
      done
      [ "${#formulae[@]}" -gt 0 ] && \
        echo "brew install ${formulae[*]}"
      [ "${#casks[@]}" -gt 0 ] && \
        echo "brew install --cask ${casks[*]}"
      ;;
    Linux)
      local pkgs=() t names
      for t in "${missing[@]}"; do
        names=($(map_pkg "$t"))
        pkgs+=("${names[@]}")
      done
      case "$distro_id" in
        arch)
          echo "sudo pacman -S --needed ${pkgs[*]}"
          ;;
        debian|ubuntu)
          echo "sudo apt-get update && sudo apt-get install -y ${pkgs[*]}"
          ;;
        fedora)
          echo "sudo dnf install -y ${pkgs[*]}"
          ;;
        opensuse*|sled|sles)
          echo "sudo zypper install -y ${pkgs[*]}"
          ;;
        alpine)
          echo "sudo apk add --no-cache ${pkgs[*]}"
          ;;
        *)
          echo "Install manually: ${pkgs[*]}"
          ;;
      esac
      ;;
    *)
      echo "Install manually: ${missing[*]}"
      ;;
  esac
}

echo "OS: $os_name${distro_id:+ ($distro_id)}"
if cmd="$(find_godot)"; then
  echo "Godot: $cmd"
else
  echo "Godot: not found"
fi

if [ "${#missing[@]}" -eq 0 ]; then
  echo "All good: rsync curl npm python3 godot"
  exit 0
fi

echo "Missing: ${missing[*]}"
echo "Try:"
install_hint
exit 1
