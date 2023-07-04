{ lib
, pkgs
, substituteAll
, runtimeShell
, coreutils
, findutils
, gnugrep
, gnused
, gitMinimal

, inputs
, runCommandLocal
}:

let
  script = substituteAll {
    name = "nuke-homebrew-repository";
    src = ./nuke-homebrew-repository.sh.in;
    isExecutable = true;

    inherit runtimeShell;
    path = lib.makeBinPath [ coreutils findutils gnugrep gnused gitMinimal ];
  };

  brew-src = inputs.brew-src or (throw "The tests can only be run with flakes");

  test-nuke = runCommandLocal "test-nuke" {
    nativeBuildInputs = [ gitMinimal ];
  } ''
    must_exist() {
      if [[ ! -e "$1" ]]; then
        >&2 echo "Error: $1 should have been kept"
        exit 1
      fi
    }

    must_not_exist() {
      if [[ -e "$1" ]]; then
        >&2 echo "Error: $1 should have been deleted"
        exit 1
      fi
    }

    # Set up test Homebrew repo
    cp -R ${brew-src}/ brew
    chmod -R u+w brew
    pushd brew >/dev/null
    git init -q
    git add -f -A
    git -c "user.name=CI" -c "user.email=ci@invalid.tld" commit -qm "Test"
    popd >/dev/null

    # Create a fake tap
    mkdir -p brew/Library/Taps/apple/homebrew-apple
    touch brew/Library/Taps/apple/homebrew-apple/content

    # Create a fake package
    mkdir -p brew/Library/Cellar/some-package/1.0.0
    touch brew/Library/Cellar/some-package/1.0.0/content
    touch brew/bin/some-command

    ${script} brew

    must_not_exist "brew/README.md"
    must_not_exist "brew/Library/Homebrew"

    must_exist "brew/Library/Taps/apple/homebrew-apple/content"
    must_exist "brew/Library/Cellar/some-package/1.0.0/content"
    must_exist "brew/bin/some-command"

    >>$out echo "Success"
  '';
in script // {
  passthru.tests = {
    inherit test-nuke;
  };
}
