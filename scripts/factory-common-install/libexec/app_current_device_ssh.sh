#!/usr/bin/env bash
common_factory_install_libexec_dir="$(pkg-nixos-factory-common-install-get-libexec-dir)"
# Source all dependencies:
. "$common_factory_install_libexec_dir/ssh.sh"
. "$common_factory_install_libexec_dir/prompt.sh"
. "$common_factory_install_libexec_dir/app_factory_info_store.sh"
. "$common_factory_install_libexec_dir/app_current_device_store.sh"




read_or_prompt_for_current_device__hostname() {
  local out_varname="$1"
  local out="null"
  if is_current_device_specified; then
    out="$(get_resolved_current_device_hostname)" || return 1
  fi

  if [[ "$out" == "null" ]] || [[ "$out" == "" ]]; then
    prompt_for_mandatory_parameter "$out_varname" "hostname"
  else
    eval "${out_varname}=${out}"
  fi
}


read_or_prompt_for_current_device__ssh_port() {
  local out_varname="$1"
  local out=""
  if is_current_device_specified; then
    out="$(get_resolved_current_device_ssh_port)" || return 1
  fi

  # TODO: auto -> retrieve from backend (e.g.: vbox backend).
  if [[ "$out" == "auto" ]]; then
    out="2222"
  fi

  if [[ "$out" == "null" ]] || [[ "$out" == "" ]]; then
    prompt_for_optional_parameter "$out_varname" "ssh_port"
  else
    eval "${out_varname}=${out}"
  fi
}


enter_ssh_as_user() {
  local user="$1"
  shift 1

  local device_hostname
  local device_ssh_port
  read_or_prompt_for_current_device__hostname "device_hostname"
  read_or_prompt_for_current_device__ssh_port "device_ssh_port"

  local ssh_port_args_a=()
  build_ssh_port_args_for_ssh_port_a "ssh_port_args_a" "$device_ssh_port"

  local ssh_args_a=( "${ssh_port_args_a[@]}" "$@" "${user}@${device_hostname}")

  echo " -> ssh" "${ssh_args_a[@]}"
  ssh "${ssh_args_a[@]}"
}


enter_ssh_as_root() {
  enter_ssh_as_user "root" "$@"
}


run_cmd_as_user() {
  local user="$1"
  local cmd="$2"
  shift 2
  local device_hostname
  device_hostname="$(get_required_current_device_hostname)" || return 1
  local device_ssh_port
  device_ssh_port="$(get_required_current_device_ssh_port)" || return 1

  local ssh_port_args_a=()
  build_ssh_port_args_for_ssh_port_a "ssh_port_args_a" "$device_ssh_port"

  local ssh_args_a=( "${ssh_port_args_a[@]}" "$@" "${user}@${device_hostname}" "$cmd")

  # 1>&2 echo "ssh" "${ssh_args_a[@]}"

  ssh "${ssh_args_a[@]}"
  # TODO: Consider these options:
  # local connect_timeout_s=3
  # ssh -o "ConnectTimeout=${connect_timeout_s}" "${ssh_args_a[@]}"
  # local timeout_s="3"
  # timeout -v "$timeout_s" ssh "${ssh_args_a[@]}"
}


run_cmd_as_device_root() {
  run_cmd_as_user "root" "$@"
}


copy_nix_closure_to_device() {
  print_title_lvl3 "Copy nix closure to device"
  local store_path="$1"

  local device_hostname
  local device_ssh_port
  read_or_prompt_for_current_device__hostname "device_hostname"
  read_or_prompt_for_current_device__ssh_port "device_ssh_port"


  # local runtime_deps_store_paths
  # echo "nix-store -q --references '$store_path'"
  # runtime_deps_store_paths="$(nix-store -q --references "$store_path")"

  # echo "runtime_deps_store_paths:"
  # echo "$runtime_deps_store_paths" | awk '{ print "  "$0}'

  local ssh_port_args
  ssh_port_args="$(build_ssh_port_args_for_ssh_port "$device_ssh_port")"

  echo "NIX_SSHOPTS='${ssh_port_args}' nix copy --to root@${device_hostname} '\$store_path'"
  export NIX_SSHOPTS="${ssh_port_args}"
  # echo "$runtime_deps_store_paths" | xargs nix copy --to root@${device_hostname}
  echo "$store_path" | xargs nix copy --to "ssh://root@${device_hostname}"
}


build_nix_derivation_locally_and_install_it_on_device() {
  print_title_lvl2 "Building nix derivation and sending it to device"
  local derivation_path="$1"

  local store_path
  echo "nix-build --no-out-link '$derivation_path'"
  store_path="$(nix-build --no-out-link "$derivation_path")"

  echo "copy_nix_closure_to_device '$store_path'"
  copy_nix_closure_to_device "$store_path"

  echo "run_cmd_as_device_root 'nix-env -q | xargs -r nix-env -e"
  run_cmd_as_device_root "nix-env -q | xargs -r nix-env -e"
  echo "run_cmd_as_device_root 'nix-env -i $store_path'"
  run_cmd_as_device_root "nix-env -i $store_path"
  # /nix-support/propagated-user-env-packages
}


deploy_factory_ssh_id_to_device() {
  print_title_lvl1 "Deploy factory ssh id to device."

  local device_hostname
  local device_ssh_port
  read_or_prompt_for_current_device__hostname "device_hostname"
  read_or_prompt_for_current_device__ssh_port "device_ssh_port"

  local ssh_port_args="$(build_ssh_port_args_for_ssh_port "$device_ssh_port")"

  # The following is to prevent the "ERROR: Host key verification failed."
  # and / or "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!"
  # one gets when attempting ssh to different machines (with different
  # host id) through the same hostname:port.
  local knownhost_id="$(build_knownhost_id_from_hostname_and_opt_port "$device_hostname" "$device_ssh_port")"
  echo "ssh-keygen -R '$knownhost_id'"
  ssh-keygen -R "$knownhost_id"

  # Note the "PubkeyAuthentication=no" option. This is to prevent the
  # "Too many Authentication Failures for user root" one gets if he
  # has too many public keys on his system.
  echo "ssh-copy-id${ssh_port_args} .. root@${device_hostname}"
  ssh-copy-id${ssh_port_args} \
    -o PubkeyAuthentication=no -o StrictHostKeyChecking=no \
    root@${device_hostname}
}


install_factory_tools_on_device() {
  print_title_lvl1 "Install factory tools on device."

  local device_type_factory_install_dir
  device_type_factory_install_dir="$(get_required_current_device_type_factory_install_root_dir)"
  # local derivation_path="$device_type_factory_install_dir/scripts/install/release.nix"
  local derivation_path="$device_type_factory_install_dir/scripts/install/env.nix"
  echo "build_nix_derivation_locally_and_install_it_on_device '$derivation_path'"
  build_nix_derivation_locally_and_install_it_on_device "$derivation_path"
}


uninstall_factory_tools_from_device() {
  print_title_lvl1 "Uninstall factory tools from device."
  run_cmd_as_device_root 'nix-env -e "nixos-device-type-install-scripts-env"'
}


deploy_file_to_device() {
  local local_f="$1"
  local remote_f="$2"

  local local_dirname
  local_dirname="$(dirname "$local_f")"

  local device_hostname
  local device_ssh_port
  read_or_prompt_for_current_device__hostname "device_hostname"
  read_or_prompt_for_current_device__ssh_port "device_ssh_port"

  local scp_port_args="$(build_scp_port_args_for_ssh_port "$device_ssh_port")"

  run_cmd_as_device_root "mkdir -m 700 -p '$local_dirname'"
  scp${scp_port_args} "${local_f}" root@${device_hostname}:${remote_f}
}


retrieve_file_from_device() {
  local local_f="$1"
  local remote_f="$2"

  local local_dirname
  local_dirname="$(dirname "$local_f")"

  local device_hostname
  local device_ssh_port
  read_or_prompt_for_current_device__hostname "device_hostname"
  read_or_prompt_for_current_device__ssh_port "device_ssh_port"

  local scp_port_args="$(build_scp_port_args_for_ssh_port "$device_ssh_port")"

  mkdir -m 700 -p "$local_dirname"
  scp${scp_port_args} "root@${device_hostname}:${remote_f}" "${local_f}"
}
