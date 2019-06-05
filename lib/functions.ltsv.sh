#!/bin/bash

_ltsv_separator=${_ltsv_separator:-$'\t'}

ltsv_encode_string() {
  local orig_txt="$1"
  local enc_txt

  unset _ltsv_encoded

  enc_txt="$orig_txt"
  enc_txt=${enc_txt// /\#\\s\#}
  enc_txt=${enc_txt//$'\t'/\#\\t\#}
  enc_txt=${enc_txt//$'\n'/\#\\n\#}

  _ltsv_encoded="$enc_txt"

  [ -n "$_ltsv_print" ] && printf '%s\n' "$_ltsv_encoded"

  return 0
}

ltsv_decode_string() {
  local orig_txt="$1"
  local dec_txt

  unset _ltsv_decoded

  dec_txt="$orig_txt"
  dec_txt="${dec_txt//\#\\t\#/$'\t'}"
  dec_txt="${dec_txt//\#\\n\#/$'\n'}"

  _ltsv_decoded="$dec_txt"

  [ -n "$_ltsv_print" ] && printf '%s\n' "$_ltsv_decoded"

  return 0
}

ltsv_get_raw_value() {
  local key="$1"
  local line="${2:-$_ltsv_line}"

  unset _ltsv_raw_value _ltsv_value

  local value tmp_vl_1

  if [[ "$line" == $key:* ]]; then
    # parameter is the first one on the line
    tmp_vl_1=${line#*:}
    value=${tmp_vl_1%%$'\t'*}
  elif [[ "$line" == *$'\t'$key:* ]]; then
    # value is after the first position on the line
    tmp_vl_1=${line#*$'\t'$key:}
    value=${tmp_vl_1%%$'\t'*}
  else
    return 1
  fi

  _ltsv_raw_value="$value"

  [ -n "$_ltsv_print" ] && printf '%s\n' "$_ltsv_raw_value"

  return 0
}

ltsv_get_value() {
  ltsv_get_raw_value "$@" >/dev/null || return $?

  ltsv_decode_string "$_ltsv_raw_value" >/dev/null && \
  _ltsv_value="$_ltsv_decoded"

  [ -n "$_ltsv_print" ] && printf '%s\n' "$_ltsv_value"

  return 0
}

 
ltsv_keys_to_line() {
  _ltsv_line=""
  local key value value_enc
  local -i arg_n=0
  
  while [ -n "$1" ]; do
    arg_n+=1
    
    key=${1%%:*}
    value=${1#*:}

    if [ -z "$key" ]; then
      unset _ltsv_line
      echo "$FUNCNAME(): missing key on argument number $arg_n" 1>&2
      return 1
    elif [ -z "$value" ]; then
      unset _ltsv_line
      echo "$FUNCNAME(): missing value on argument number $arg_n" 1>&2
      return 1
    fi

    ltsv_encode "$value" && value_enc="$_ltsv_encoded" ||
      { unset _ltsv_line ; return 1; }

      if [ ${#_ltsv_line} -eq 0 ]; then
        _ltsv_line="$key:$value_enc"
      else
        _ltsv_line+=$'\t'"$key:$value_enc"
      fi
  done
}

ltsv_get_line_from_file() {
  local file="${1:-$_ltsv_file}"
  local st line
  unset _ltsv_line
    
  IFS=$'\t' read line < "$file"
  st=$?
  [ $st -ne 0 ] && return $st

  if [ -z "$line" ]; then
    echo "$FUNCNAME(): got an empty line" 1>&2
    return 1
  fi

  if [ "${line:0:1}" == "#" ]; then
    echo "$FUNCNAME(): got commented line" 1>&2
    return 1
  fi

  _ltsv_line="$line"
}

ltsv_parse_line_into_namespace() {
  local namespace="$1"
  local line="${2:-$_ltsv_line}"
  local -a params_ar=()
  local _param _key _value _key_esc _value_enc

  cleanup_namespace $namespace

  while [ "${line}" != "${line# }" ]; do
    line=${line# } # remove leading spaces
  done

  IFS="$_ltsv_separator" read -a params_ar <<< "$line"

  for _param in "${params_ar[@]}"; do
    _key=${_param%%:*}
    _value_enc=${_param#*:}
    
    ltsv_decode_string "$_value_enc"
    _value="$_ltsv_decoded"

    _key_esc=${_key//[^a-zA-Z0-9_]/_}
    _key_esc=${_key_esc//__/_}

    set_global_var ${namespace}__${_key_esc} "$_value"
  done
}

ltsv_load_line_from_file_into_namespace() {
  local namespace="$1"
  local file="$2"

  ltsv_get_line_from_file "$file" || return $?

  ltsv_parse_line_into_namespace "$namespace"
}

ltsv_namespace_to_string() {
  local namespace="$1"
  local key key_esc value value_esc raw_var

  _ltsv_value=""

  for raw_var in $(eval echo \${!${namespace}__*}); do
    if [ -z "${!raw_var}" ]; then
      continue
    else
      value="${!raw_var}"
    fi

    key=${raw_var#${namespace}__}

    ltsv_encode_string "$key" && \
    key_esc="$_ltsv_encoded"

    ltsv_encode_string "$value" && \
    value_esc="$_ltsv_encoded"

    if [ -n "$_ltsv_value" ]; then
      _ltsv_value+="$_ltsv_separator"
    fi

    _ltsv_value+="$key_esc:$value_esc"
  done

  [ -n "$_ltsv_value" ]
}

ltsv_save_namespace_to_file() {
  local namespace="$1"
  local filename="$2"

  local raw_var key key_esc value value_esc
  local txt_str=""

  for raw_var in $(eval echo \${!${namespace}__*}); do
    if [ -z "${!raw_var}" ]; then
      continue
    else
      value="${!raw_var}"
    fi

    key=${raw_var#${namespace}__}

    ltsv_encode_string "$key" && \
    key_esc="$_ltsv_encoded"

    ltsv_encode_string "$value" && \
    value_esc="$_ltsv_encoded"

    if [ -n "$txt_str" ]; then
      txt_str+="$_ltsv_separator"
    fi

    txt_str+="$key_esc:$value_esc"
  done

  if [ -n "$txt_str" ]; then
    echo "$txt_str" >$filename
  else
    echo "$FUNCNAME(): error, empty namespace '$namespace'" 1>&2
    return 1
  fi
}
