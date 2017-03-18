# Dynamic-DNS-IP-Updater
Updates the public IPv4 address (if changed) at DNS or DynDNS services DuckDNS, INWX, TwoDNS, DO.de

- retrieves and caches the public IPv4 address 
- if IP has changed
  - en email is sent
  - DNS entries at DuckDNS, INWX, TwoDNS, DO.de are updated

For dynamic DNS this script is to be executed every few minutes (e.g. using cron).

Usage: perl dns-ip-updater.pl

Requires: perl with XMLRPC::Lite (Ubuntu: libxmlrpc-lite-perl)
