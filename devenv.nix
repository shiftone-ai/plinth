{ pkgs, ... }:

# Plinthの開発シェル．
#
# Swiftのtoolchain・SDK・swift-formatはXcodeのものを使う．nixpkgsのSwiftは
# Package.swiftのswift-tools-version 6.4に届かないため，Nixでは入れない．
# NixはXcodeに含まれない検査ツールの版を固定する．

let
  xcrun = "/usr/bin/xcrun";
in
{
  # nixpkgsのapple-sdkとC compilerを入れず，xcode-selectで選んだXcodeを使う．
  apple.sdk = null;
  stdenv = pkgs.stdenvNoCC;
  # stdenvが入れる値で，Package.swiftとXcode projectのdeployment targetを上書きさせない．
  unsetEnvVars = [ "MACOSX_DEPLOYMENT_TARGET" ];

  # justfileが呼ぶ道具．
  packages = with pkgs; [
    gitleaks
    just
    nixfmt
    ruff
    shfmt
    swiftlint
  ];

  # commit前は変更したファイルだけを整形・検査し，push前にビルドとテストを通す．
  # hookはdevenvのシェルの外からも動くよう，実行ファイルを絶対パスで呼ぶ．
  git-hooks.hooks = {
    swift-format = {
      enable = true;
      name = "swift-format";
      entry = "${xcrun} swift-format format --in-place";
      types = [ "swift" ];
    };
    swift-format-lint = {
      enable = true;
      name = "swift-format lint";
      entry = "${xcrun} swift-format lint --strict";
      types = [ "swift" ];
      after = [ "swift-format" ];
    };
    swiftlint = {
      enable = true;
      name = "SwiftLint";
      entry = "${pkgs.swiftlint}/bin/swiftlint lint --quiet --baseline .swiftlint-baseline.json";
      types = [ "swift" ];
      after = [ "swift-format" ];
    };
    ruff.enable = true;
    ruff-format.enable = true;
    shfmt.enable = true;
    nixfmt.enable = true;
    gitleaks.enable = true;
    # 文書の句読点は「，．」にそろえる．vendorのSkillは取得元の表記を保つ．
    ja-punctuation = {
      enable = true;
      name = "Japanese punctuation";
      entry = "${pkgs.python3}/bin/python3 scripts/check-ja-punctuation.py";
      types = [ "markdown" ];
      excludes = [ "^\\.agents/skills/" ];
    };
    public-content = {
      enable = true;
      name = "Public content";
      entry = "${pkgs.python3}/bin/python3 scripts/check-public-content.py --staged";
      pass_filenames = false;
      always_run = true;
    };
    swift-test = {
      enable = true;
      name = "swift test";
      entry = "${pkgs.just}/bin/just test";
      pass_filenames = false;
      always_run = true;
      stages = [ "pre-push" ];
    };
  };

  # devenv testは全ファイルへのcommit前hookを実行してから，ここでテストを走らせる．
  enterTest = ''
    just test
  '';
}
