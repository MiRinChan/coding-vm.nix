{
  lib,
  settings,
}: let
  version = settings.defaultsVersion or 1;
  defaults =
    if version == 1
    then import ../profiles/v1.nix
    else if version == 2
    then import ../profiles/v2.nix
    else throw "Unsupported defaultsVersion ${toString version}. Keep the existing generation or migrate its settings.";
  unknown = path: supplied: expected:
    lib.concatMap (
      name: let
        key = path ++ [name];
      in
        if !(builtins.hasAttr name expected)
        then [lib.concatStringsSep "." key]
        else if builtins.isAttrs supplied.${name} && builtins.isAttrs expected.${name}
        then unknown key supplied.${name} expected.${name}
        else []
    ) (builtins.attrNames supplied);
  invalid = unknown [] settings defaults;
  result = lib.recursiveUpdate defaults settings;
in
  if invalid != []
  then throw "Unknown instance settings: ${lib.concatStringsSep ", " invalid}"
  else
    assert builtins.match "[a-zA-Z0-9_-]+" result.launcher.sshAlias != null;
    assert result.launcher.sshPort > 0 && result.launcher.sshPort < 65536;
    assert builtins.elem result.kernel.source ["cachyos" "nixpkgs"]; result
