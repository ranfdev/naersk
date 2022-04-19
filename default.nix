{ cargo
, darwin
, fetchurl
, jq
, lib
, lndir
, remarshal
, rsync
, runCommandLocal
, rustc
, stdenv
, writeText
, zstd
} @ defaultBuildAttrs:

let
  libb = import ./lib.nix {
    inherit lib writeText runCommandLocal remarshal;
  };

  builtinz = builtins // import ./builtins {
    inherit lib writeText remarshal runCommandLocal;
  };

  mkConfig = arg: import ./config.nix {
    inherit lib arg libb builtinz;
  };

  buildPackage = arg:
    let
      config = mkConfig arg;

      gitDependencies = libb.findGitDependencies {
        inherit (config) cargolock gitAllRefs gitSubmodules;
      };

      cargoconfig =
        if builtinz.pathExists (toString config.root + "/.cargo/config")
          then builtins.readFile (config.root + "/.cargo/config")
          else null;

      build = args: import ./build.nix (
        {
          inherit gitDependencies;
          version = config.packageVersion;
        } // config.buildConfig // defaultBuildAttrs // args
      );

      buildDeps =
        build {
          inherit (config) userAttrs;

          pname = "${config.packageName}-deps";

          src = libb.dummySrc {
            inherit cargoconfig;
            inherit (config) cargolock cargotomls copySources copySourcesFrom;
          };

          copyTarget = true;
          copyBins = false;
          copyBinsFilter = ".";
          copyDocsToSeparateOutput = false;
          builtDependencies = [];

          # TODO: custom cargoTestCommands should not be needed here
          cargoTestCommands = map (cmd: "${cmd} || true") config.buildConfig.cargoTestCommands;
        };

      buildTopLevel =
        let
          drv = build {
            inherit (config) userAttrs src;

            pname = config.packageName;
            builtDependencies = lib.optional (! config.isSingleStep) buildDeps;
          };

        in
        drv.overrideAttrs config.overrideMain;

    in
    buildTopLevel;

in
{
  inherit buildPackage;
}
