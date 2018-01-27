get_kernel_version() {
  local str_1 str_2 version_str

  read str_1 str_2 version_str < /proc/version

  if [ -n "$version_str" ]; then
    echo "$version_str"
    return 0
  else
    echo "$FUNCNAME(): unable to get kernel version" 1>&2
    return 1
  fi
}

get_free_ram() {
  # echoes the available free ram in MB
  local kernel_version major minor patch
  kernel_version=$(get_kernel_version) || return $?

  IFS=. read major minor patch <<< "$kernel_version"
  if [ -n "$major" -a -n "$minor" -a $major -ge 3 -a $minor -ge 14 ]; then
    get_free_ram_k3_14
  else
    get_free_ram_before_k3_14
  fi
}

get_free_ram_k3_14() {
  # for kernel 3.14 and beyond

  unset _dp_value
  local key value unit free_ram_n
  # MemAvailable:   10607888 kB
  while read key value unit ; do
    [ -z "$key" -o -z "$value" -o -z "$unit" ] && continue

    if [ "$key" == "MemAvailable:" -a "$unit" == kB ]; then
      free_ram_n=$(( $value / 1024 ))
      echo "$free_ram_n"
      return 0
    fi
  done < /proc/meminfo

  return 1
}

get_free_ram_before_k3_14() {
  # for kernels older than 3.14
  local mem_free_n mem_cached_n free_ram_n
  while read key value unit; do
    if [ "$key" == "MemFree:" -a "$unit" == "kB" ]; then
      mem_free_n=$(( $value / 1024 ))
    elif [ "$key" == "Cached:" -a "$unit" == "kB" ]; then
      mem_cached_n=$(( $value / 1024 ))
    fi

    if [ -n "$mem_free_n" -a -n "$mem_cached_n" ]; then
      free_ram_n=$(( $mem_free_n + $mem_cached_n ))
      echo "$free_ram_n"
      return 0
    fi
  done < /proc/meminfo

  return 1
}

has_a_safe_level_of_free_ram() {
  local -i n_curr_free n_min_free_safe
  n_min_free_safe=${2:-100}
  
  n_curr_free=$(get_free_ram) || return $?

  if [ $n_curr_free -gt $n_min_free_safe ]; then
    return 0
  else
    return 1
  fi
}
