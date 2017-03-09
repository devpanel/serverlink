# this file contains shared functions common to Debian and Ubuntu

add_apt_repositories() {
  local sys_dir="$1"
  local distro="$2"
  local distro_ver="$3"
  local distro_ver_major="$4"
  local distro_ver_minor="$5"

  local distro_config_dir="$source_dir/config/os.$distro"
  local repos_dir_tmpl="$distro_config_dir/@version@/repositories"
  local distro_ver_major_minor="$distro_ver_major.$distro_ver_minor"

  local repos_link repos_file repos_name key_link t_dir
  local repos_dir_1 repos_dir_2 repos_dir_3
  local pref_file pref_name

  repos_dir_1="${repos_dir_tmpl//@version@/$distro_ver}"
  repos_dir_2="${repos_dir_tmpl//@version@/$distro_ver_major_minor}"
  repos_dir_3="${repos_dir_tmpl//@version@/$distro_ver_major}"

  for repos_link in "$repos_dir_1/repos."[0-9]*.* \
                    "$repos_dir_2/repos."[0-9]*.* \
                    "$repos_dir_3/repos."[0-9]*.*; do

    if [ ! -L "$repos_link" ]; then
      continue
    fi

    repos_name="${repos_link##*.}"
    t_dir="${repos_link%/*}"
    repos_file=$(readlink -e "$repos_link")
    if [ $? -ne 0 ]; then
      echo "$FUNCNAME(): warning, link $repos_link doesn't resolve" 1>&2
      sleep 2
      continue
    fi

    cp -f "$repos_file" /etc/apt/sources.list.d

    key_link="$t_dir/$repos_name.key"
    if [ -L "$key_link" -a -f "$key_link" ]; then
      apt-key add "$key_link"
      if [ $? -ne 0 ]; then
        echo "$FUNCNAME(): error - unable to add key from file $key_link" 1>&2
        return 1
      fi
    fi
  done

  for pref_file in "$repos_dir_1"/preferences.*  \
                    "$repos_dir_2"/preferences.* \
                    "$repos_dir_3"/preferences.* ; do

    if [ ! -f "$pref_file" ]; then
      continue
    fi

    pref_name="${pref_file##*.}"
    cp -f "$pref_file" "/etc/apt/preferences.d/$pref_name"
  done

  return 0
}
