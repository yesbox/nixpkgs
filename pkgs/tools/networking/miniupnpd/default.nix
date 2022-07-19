{ stdenv, lib, fetchurl, iptables, libuuid, pkg-config
, which, iproute2, gnused, coreutils, gawk, makeWrapper
, nixosTests
}:

let
  scriptBinEnv = lib.makeBinPath [ which iproute2 iptables gnused coreutils gawk ];
in
stdenv.mkDerivation rec {
  pname = "miniupnpd";
  version = "2.3.0";

  src = fetchurl {
    url = "http://miniupnp.free.fr/files/download.php?file=miniupnpd-${version}.tar.gz";
    hash = "sha256-/56V42DHuq51dXW1utwhqxxkPTWZVvloVAtPgCb6z5w=";
    name = "miniupnpd-${version}.tar.gz";
  };

  buildInputs = [ iptables libuuid ];
  nativeBuildInputs= [ pkg-config makeWrapper ];

  makefile = "Makefile.linux";

  buildFlags = [ "miniupnpd" ];

  dontAddPrefix = true;
  installFlags = [ "PREFIX=$(out)" "INSTALLPREFIX=$(out)" ];

  postFixup = ''
    for script in $out/etc/miniupnpd/ip{,6}tables_{init,removeall}.sh
    do
      wrapProgram $script --set PATH '${scriptBinEnv}:$PATH'
    done
  '';

  passthru.tests = {
    bittorrent-integration = nixosTests.bittorrent;
  };

  meta = with lib; {
    homepage = "http://miniupnp.free.fr/";
    description = "A daemon that implements the UPnP Internet Gateway Device (IGD) specification";
    platforms = platforms.linux;
    license = licenses.bsd3;
  };
}
