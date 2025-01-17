{ stdenv
, lib
, makeWrapper
, nixos-common-install-scripts
, nixos-device-system-config
, openssh
, yq
, jq
, sshfs-fuse
, pwgen
, mkpasswd
, screen
, socat
, picocom
, python3
, virtualbox
, mr
, xclip
, diffutils
, bashInteractive
, nix-prefetch-git
, nix-prefetch-github
}:

stdenv.mkDerivation rec {
  version = "0.0.0";
  pname = "nixos-factory-common-install";
  name = "${pname}-${version}";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  propagatedUserEnvPkgs = [
    nixos-common-install-scripts
    nixos-device-system-config
  ];

  propagatedBuildInputs = [
    mr
    nixos-common-install-scripts
    nixos-device-system-config
  ];

  buildInputs = [
    nixos-common-install-scripts
    nixos-device-system-config
    mr # Simplifies working with multiple repos.

    # TODO: Consider removing the openssh dep as the nix
    # version might not work on non-nixos.
    openssh # ssh, sftp, scp, ssh-keygen
    yq # yaml manipulations
    jq # json manipulations
    sshfs-fuse
    pwgen
    mkpasswd

    screen
    socat
    picocom
    (python3.withPackages (pp: with pp; [
        pytest
        ipython
      ])
    )

    # TODO: Consider this. Not certain if nix would be capable
    # of introducing this dependency on non nix system as it
    # requires a setuid wrapper.
    # virtualbox

    xclip
    diffutils

    nix-prefetch-git
    nix-prefetch-github
  ];

  postPatch = ''
    substituteInPlace ./bin/pkg-${pname}-get-libexec-dir \
      --replace 'default_pkg_dir=' '# default_pkg_dir=' \
      --replace '$default_pkg_dir/libexec' "$out/share/${pname}/libexec"

    substituteInPlace ./bin/pkg-${pname}-get-root-dir \
      --replace 'default_pkg_dir=' '# default_pkg_dir=' \
      --replace '$default_pkg_dir' "$out/share/${pname}"

    ! test -e "./.local-env.sh" || rm ./.local-env.sh
  '';


  pythonPathDeps = lib.strings.makeSearchPath "python-lib" [
  ];

  binPathDeps = stdenv.lib.makeBinPath buildInputs;


  installPhase = ''
    mkdir -p "$out/share/${pname}"
    find . -mindepth 1 -maxdepth 1 -exec mv -t "$out/share/${pname}" {} +

    mkdir -p "$out/bin"
    for cmd in $(find "$out/share/${pname}/bin" -mindepth 1 -maxdepth 1); do
      target_cmd_basename="$(basename "$cmd")"
      makeWrapper "$cmd" "$out/bin/$target_cmd_basename" \
        --prefix PATH : "${binPathDeps}" \
        --prefix PATH : "$out/share/${pname}/bin" \
        --prefix PYTHONPATH : "$out/share/${pname}/python-lib" \
        --prefix PYTHONPATH : "${pythonPathDeps}"
    done
  '';

  preFixup = ''
    PATH="${bashInteractive}/bin:$PATH" patchShebangs "$out"
  '';

  shellHook = ''
    export PATH="${src}/bin:''${binPathDeps:+:}$binPathDeps''${PATH:+:}$PATH"
    export PYTHONPATH="${src}/python-lib''${pythonPathDeps:+:}$pythonPathDeps''${PYTHONPATH:+:}$PYTHONPATH"
  '';

  meta = {
    description = ''
      Some scripts meant to be run by the factory technician
      to install nixos on new devices.
    '';
  };

}
