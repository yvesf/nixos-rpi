{ lib, fetchFromGitHub, rustPlatform,
  pkg-config, openssl }:

rustPlatform.buildRustPackage rec {
  pname = "ebus";
  version = "ebus-rust"; # it's a branch
  src = fetchFromGitHub {
    owner = "yvesf";
    repo = pname;
    rev = version;
    sha256 = "sha256-HYodCTx2c7K1YYc2CnLI1nUhMBTIwK7FA9mKU/k759I=";
  };
  cargoSha256 = "sha256-Dd7g3w7zEyCMvYO2sTtNV+A1djyQnsbXpMocdyXXk0s=";
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ openssl ] ;
  sourceRoot = "source/ebus-rust";
}
