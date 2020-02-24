# This tests whether UPnP and NAT-PMP port mappings can be created
# using Miniupnpd, Miniupnpc and Libnatpmp.
#
# It runs a Miniupnpd service on one machine, and verifies
# a machine hosting a server can indeed create and remove
# port mappings using Miniupnpc and Libnatpmp.
#
# An external client will try to connect to the port
# mapping both when the it's opened and closed.

import ./make-test-python.nix ({ pkgs, ... }:

let
  internalRouterAddress = "192.168.3.1";
  internalServerAddress = "192.168.3.2";
  externalRouterAddress = "80.100.100.1";
  externalClientAddress = "80.100.100.2";
in
{
  name = "upnp";
  meta = with pkgs.stdenv.lib.maintainers; {
    maintainers = [ bobvanderlinden ];
  };

  nodes =
    {
      router =
        { pkgs, nodes, ... }:
        { virtualisation.vlans = [ 1 2 ];
          networking.nat.enable = true;
          networking.nat.internalInterfaces = [ "eth2" ];
          networking.nat.externalInterface = "eth1";
          networking.firewall.enable = true;
          networking.firewall.trustedInterfaces = [ "eth2" ];
          networking.firewall.rejectPackets = true;
          networking.interfaces.eth1.ipv4.addresses = [
            { address = externalRouterAddress; prefixLength = 24; }
          ];
          networking.interfaces.eth2.ipv4.addresses = [
            { address = internalRouterAddress; prefixLength = 24; }
          ];
          services.miniupnpd = {
            enable = true;
            upnp = true;
            natpmp = true;
            externalInterface = "eth1";
            internalIPs = [ internalRouterAddress ];
            appendConfig = ''
              ext_ip=${externalRouterAddress}
            '';
          };
        };

      internalServer =
        { pkgs, nodes, ... }:
        { virtualisation.vlans = [ 2 ];
          environment.systemPackages = [ pkgs.miniupnpc_2 pkgs.libnatpmp ];
          networking.defaultGateway = internalRouterAddress;
          networking.interfaces.eth1.ipv4.addresses = [
            { address = internalServerAddress; prefixLength = 24; }
          ];
          networking.firewall.enable = false;

          services.httpd.enable = true;
          services.httpd.virtualHosts.localhost = {
            listen = [
              { ip = "*"; port = 9001; }
              { ip = "*"; port = 9002; }
            ];
            adminAddr = "foo@example.org";
            documentRoot = "/tmp";
          };
        };

      externalClient =
        { pkgs, ... }:
        { virtualisation.vlans = [ 1 ];
          networking.interfaces.eth1.ipv4.addresses = [
            { address = externalClientAddress; prefixLength = 24; }
          ];
        };
    };

  testScript =
    { nodes, ... }:
    ''
      start_all()

      # Wait for router network and miniupnpd
      router.wait_for_unit("network-online.target")
      router.wait_for_unit("firewall.service")
      router.wait_for_unit("miniupnpd")

      # Wait for server
      internalServer.wait_for_unit("network-online.target")
      internalServer.wait_for_unit("httpd")

      # Wait for client network and ensure the server is not yet reachable
      externalClient.wait_for_unit("network-online.target")
      externalClient.fail("curl --fail http://${externalRouterAddress}:9001/")
      externalClient.fail("curl --fail http://${externalRouterAddress}:9002/")

      ## uPnP open
      internalServer.succeed("upnpc -a ${internalServerAddress} 9001 9001 TCP")
      externalClient.wait_until_succeeds("curl http://${externalRouterAddress}:9001/")

      ## uPnP close
      internalServer.succeed("upnpc -d 9001 TCP ${internalServerAddress}")
      externalClient.fail("curl --fail http://${externalRouterAddress}:9001/")

      # NAT-PMP open
      internalServer.succeed("natpmpc -g ${internalRouterAddress} -a 9002 9002 TCP 3600")
      externalClient.wait_until_succeeds("curl http://${externalRouterAddress}:9002/")

      # NAT-PMP close
      internalServer.succeed("natpmpc -g ${internalRouterAddress} -a 9002 9002 TCP 0")
      externalClient.fail("curl --fail http://${externalRouterAddress}:9002/")
    '';
})
