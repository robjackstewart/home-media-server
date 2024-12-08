$wslIP=$(wsl hostname -I).Split(' ')[0]

    netsh interface portproxy delete v4tov4 listenport=8096
    netsh interface portproxy delete v4tov4 listenport=8920
    netsh interface portproxy delete v4tov4 listenport=7359
    netsh interface portproxy delete v4tov4 listenport=1900

    Remove-NetFirewallRule -DisplayName "Open Jellyfin Port *"

    netsh interface portproxy add v4tov4 listenport=8096 connectport=8096 connectaddress=$wslIP
    netsh interface portproxy add v4tov4 listenport=8920 connectport=8920 connectaddress=$wslIP
    netsh interface portproxy add v4tov4 listenport=7359 connectport=7359 connectaddress=$wslIP
    netsh interface portproxy add v4tov4 listenport=1900 connectport=1900 connectaddress=$wslIP

    netsh advfirewall firewall add rule name="Open Jellyfin Port 8096" dir=in action=allow protocol=TCP localport=8096
    netsh advfirewall firewall add rule name="Open Jellyfin Port 8920" dir=in action=allow protocol=TCP localport=8920
    netsh advfirewall firewall add rule name="Open Jellyfin Port 7359" dir=in action=allow protocol=UDP localport=7359
    netsh advfirewall firewall add rule name="Open Jellyfin Port 1900" dir=in action=allow protocol=UDP localport=1900