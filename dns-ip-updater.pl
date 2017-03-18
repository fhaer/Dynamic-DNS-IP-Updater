#!/usr/bin/perl
# Retrieves the public IPv4 address and updates DNS entries for DuckDNS, INWX, TwoDNS, DO.de
# - the IP is cached and only updated if it has changed
# - on IP changes, an email is sent
# - for dynamicDNS this script is to be executed every few minutes (e.g. using cron)

use Socket;
use strict;
use LWP::Simple;

my $quiet = 0; # no output if set to 1
my $force = 1; # if set to 1, DNS updates are forced, even if IP is not outdated

my $cacheFileBaseName = "/tmp/updateIpAndDns-cache-";
my $cacheFileDO       = $cacheFileBaseName . "DO";
my $cacheFileInwx     = $cacheFileBaseName . "Inwx";
my $cacheFileTwoDns   = $cacheFileBaseName . "TwoDns";
my $cacheFileDuckDns  = $cacheFileBaseName . "DuckDns";

my $publicIp = getPublicIp();
`echo $publicIp >> /tmp/ip-hist`;

die "unable to retrieve public IP address\n" if (!$publicIp);

my $dnsIpDO      = readIpFromFile($cacheFileDO);
my $dnsIpInwx    = readIpFromFile($cacheFileInwx);
my $dnsIpTwoDns  = readIpFromFile($cacheFileTwoDns);
my $dnsIpDuckDns = readIpFromFile($cacheFileDuckDns);

if (dnsIpOutdated($dnsIpDO)) {
  sendEmail('from@examplenet', 'to@example.net', "IP $publicIp", "public IP changed");
  $dnsIpDO = updateCache($cacheFileDO, "www.example.net");
  updateDO($publicIp, "www.example.net") if (dnsIpOutdated($dnsIpDO));
}
if (dnsIpOutdated($dnsIpInwx)) {
  $dnsIpInwx = updateCache($cacheFileInwx, "www.example2.net");
  updateInwx($publicIp, "www.example2.net") if (dnsIpOutdated($dnsIpInwx));
}
if (dnsIpOutdated($dnsIpTwoDns)) {
  $dnsIpTwoDns = updateCache($cacheFileTwoDns, "example.dd-dns.de");
  updateTwoDns($publicIp, "example.dd-dns.de") if (dnsIpOutdated($dnsIpTwoDns));
}
if (dnsIpOutdated($dnsIpDuckDns)) {
  $dnsIpDuckDns = updateCache($cacheFileDuckDns, "example.duckdns.org");
  updateDuckDns($publicIp, "example") if (dnsIpOutdated($dnsIpDuckDns));
}

# --- SUBROUTINES --------------------------------------------------------------

# returns the public IP address
sub getPublicIp {
  print "Get Public IP\n" unless $quiet;

  # specify multiple commands with multiple servers (as a backup) to retrieve the public IP
  my $tmp = "/tmp/updateIpAndDns-publicIp";
  my @ipcheckservices = (
         # Read IP from text file (enable if MikroTik-Router-Traffic-Monitoring is used):
         #"find /tmp/mikrotik-ip.txt -newermt '-20 minutes' -exec cat {} \\;",
         # retrieve IP from akamai using dns
         "dig -4 \@ns1-1.akamaitech.net -t a whoami.akamai.net +short",
         # retrieve IP from google using dns
         "dig -4 \@ns1.google.com -t txt o-o.myaddr.l.google.com +short",
         # # retrieve IP from opendns using dns
         "dig -4 \@resolver1.opendns.com -t a myip.opendns.com +short",
         "dig -4 \@resolver2.opendns.com -t a myip.opendns.com +short",
         "dig -4 \@resolver3.opendns.com -t a myip.opendns.com +short",
         "dig -4 \@resolver4.opendns.com -t a myip.opendns.com +short",
     );

  my $ip = "";
  my $i = 0;
  # execute commands until an IP is retrieved
  while ($ip eq "" && $i < scalar(@ipcheckservices)) {
    system($ipcheckservices[$i] . " > $tmp");
    $ip = readIpFromFile($tmp);
    print "ipcheckservice $ipcheckservices[$i] returned public IP $ip\n" unless $quiet;
    print "public ip lookup failed\n" if ($ip eq "");
    $i++;
  }
  return $ip;
}

# returns 1 if public ip is outdated or if force is enabled
sub dnsIpOutdated {
  my $dnsIp = shift;
  return ($force || $publicIp ne $dnsIp);
}

# looks up and stores the IP for a given host on given nameserver (optional) to a file and returns the IP
sub updateCache {
  my $file = shift;
  my $hostname = shift;
  my $nameserver = shift;
  $nameserver = "8.8.8.8" if (!defined $nameserver);
  print "Looking up and caching IP for $hostname\n" unless $quiet;
  my $ip = nslookup($hostname, $nameserver);
  writeIpToFile($ip, $file);
  return $ip;
}

# looks up the given ip at the given name server using dig
sub nslookup {
  my $hostname = shift;
  my $nameserver = shift;
  my $tmp = "/tmp/updateIpAndDns-nslookup";
  system("dig -4 \@$nameserver -t a $hostname +short > $tmp");
  my $ip = readIpFromFile($tmp);
  print "unable to find IP address in answer from DNS-server\n" if ($ip eq "");
  return $ip;
}

# Parses file for IPv4 and returns it. Returns empty string if no ip is found.
sub readIpFromFile {
  my $file = shift;
  open I, $file;
  my $ip = "";
  while (<I>) {
    $ip = $1 if (/.*?(\d+\.\d+\.\d+\.\d+).*/);
    #$ip = $1 if (/.*?(\w+\:\w+\:\w+\:\w+\:\w+\:\w+\:\w+\:\w+).*/);  # IPv6
  }
  close I;
  print "Found IP \"$ip\" in $file\n" unless $quiet;
  return $ip;
}

# Writes an IP to a file for caching
sub writeIpToFile {
  my $ip = shift;
  my $file = shift;
  print "Caching IP \"$ip\" in $file\n" unless $quiet;
  open O, ">$file";
  print O $ip;
  close O;
}

# Sends out an email
 sub sendEmail {
  my $from = shift;
  my $recipients = shift;
  my $subject = shift;
  my $message = shift;

  use Email::Sender::Simple qw(sendmail);
  use Email::Sender::Transport::SMTP::TLS;
  use Try::Tiny;

  my $transport = Email::Sender::Transport::SMTP::TLS->new(
        host => 'INSERT_SMTP_SERVER',
        port => 587,
        username => 'USERT_SMTP_USERNAME',
        password => 'INSERT_SMTP_PASSWORD',
        helo => 'INSERT_LOCAL_HOSTNAME',
  );

  use Email::MIME::CreateHTML; # or other Email::
  my $message = Email::MIME->create_html(
        header => [
            From    => $from,
            To      => $recipients,
            Subject => $subject,
        ],
        body => $message
  );

  try {
    sendmail($message, { transport => $transport });
  } catch {
    print "Error sending email\n $_";
  };
}


# --- subroutines to update DNS ---

# Updates DNS for domains registered at INWX https://www.inwx.de/de/
# call e.g. updateInwx($publicIp, "www.example.net")
sub updateInwx {
 my $ip = shift;
 my $hostname = shift;

 my $usr = 'INSERT_USERNAME_HERE';
 my $pwd = 'INSERT_PASSWORD_HERE';

 use Data::Dumper;
 use HTTP::Cookies;
 use XMLRPC::Lite; # +trace => 'all';

 print "Updating INWX with $ip\n" unless $quiet;

 my $addr = "https://api.domrobot.com/xmlrpc/"; # Live

 my ($proxy,$result);
 $proxy = XMLRPC::Lite
      -> proxy($addr, cookie_jar => HTTP::Cookies->new(ignore_discard => 1));

 $result = $proxy->call('account.login', { user => $usr, pass => $pwd })->result;
 if ( $result->{code} == 1000 ) {  # Command completed successfully
  # get ID
  my $nsEntryId = "";
  $result = $proxy->call('nameserver.info', { type => 'A' })->result;
  foreach my $rec (@{$result->{resData}->{record}}) {
    my $n = $rec->{name};
    print "$n $rec->{id}\n";
    if ($n eq $hostname) {
      $nsEntryId = $rec->{id};
    }
  }
  print "inwx nameserver type A entry: $nsEntryId\n" unless $quiet;
  $result = $proxy->call('nameserver.updateRecord', {
        id => $nsEntryId, content => $ip, ttl => 300
  })->result;
  print Dumper($result) unless $quiet;
 } else {
  print Dumper($result) unless $quiet;
 }
}

# Updates DNS for domains registered at Domain Offensive https://www.do.de
# call e.g. updateDO($publicIp, "*.example.net") for subdomains of example.net
sub updateDO {
  my $myIp = shift;
  my $myHostname = shift;
  
  my $usr = 'INSERT_FLEX_DNS_USER';
  my $pwd = 'INSERT_FLEX_DNS_PASSWORD';
  
  print "Updating Domain Offensive FlexDNS\n" unless $quiet;
  # request url with token from duckdns website (use HTTPS only)
  my $url = 'https://' . $usr . ':' . $pwd . '@ddns.do.de/?hostname=' . $myHostname . '&myip=' . $myIp;
  print "$url\n" unless $quiet;
  my $ua = LWP::UserAgent->new;
  $ua->agent('Mozilla/5.0');
  my $resp = $ua->get($url);
  if ($resp->is_success) {
    print "ok." unless $quiet;
  } else {
    print $resp->status_line unless $quiet;
  }
}

# Updates DNS for sub-domains registered at DuckDNS https://www.duckdns.org
# call e.g. updateDuckDns($publicIp, "subdomain") for address subdomain.duckdns.org
sub updateDuckDns {
  my $myIp = shift;
  my $mySubdomain = shift;
  
  my $token = ''; # token given by duckdns website
  
  print "Updating DynDNS DuckDNS\n" unless $quiet;
  # request url with token (use HTTPS only)
  my $url = 'https://www.duckdns.org/update?domains=' . $mySubdomain . '&token=' . $token . '&ip=' . $myIp;
  print "$url\n" unless $quiet;
  my $ua = LWP::UserAgent->new;
  $ua->agent('Mozilla/5.0');
  my $resp = $ua->get($url);
  if ($resp->is_success) {
    print "ok." unless $quiet;
  } else {
    print $resp->status_line unless $quiet;
  }
}

# Updates DNS for sub-domains registered at TwoDNS https://www.twodns.de
# call e.g. updateTwoDns($publicIp, "example.twodns.de")
sub updateTwoDns {
  my $myIp = shift;
  my $myHostname = shift;
  
  my $usr = 'INSERT_USERNAME_HERE';  # in user name, replaced @ by %40 (mail@example.com => mail%40example.com)
  my $pwd = 'INSERT_PASSWORD_HERE';
  
  print "Updating DynDNS TwoDns\n" unless $quiet;
  # request url with user name and password (use HTTPS only)
  my $url = 'https://' . $usr . ':' . $pwd . '@update.twodns.de/update?hostname=' . $myHostname . '&ip=' . $myIp;
  print "$url\n" unless $quiet;
  my $ua = LWP::UserAgent->new;
  $ua->agent('Mozilla/5.0');
  my $resp = $ua->get($url);
  if ($resp->is_success) {
    print "ok." unless $quiet;
  } else {
    print $resp->status_line unless $quiet;
  }
}

# Updates DNS for sub-domains registered at no-ip.com https://www.no-ip.com
# call e.g. updateNoIp($publicIp, "example.no-ip.com")
sub updateNoIp {
  my $myIp = shift;
  my $myHostname = shift;
  
  my $usr = 'INSERT_USERNAME_HERE';
  my $pwd = 'INSERT_PASSWORD_HERE';
  
  print "Updating DynDNS No-IP\n" unless $quiet;
  # request url with user name and password (use HTTPS only)
  my $url = 'https://' . $usr . ':' . $pwd . '@dynupdate.no-ip.com/nic/update?hostname=' . $myHostname . '&myip=' . $myIp;
  print "$url\n" unless $quiet;
  my $ua = LWP::UserAgent->new;
  $ua->agent('Mozilla/5.0');
  my $resp = $ua->get($url);
  if ($resp->is_success) {
    print "ok." unless $quiet;
  } else {
    print $resp->status_line unless $quiet;
  }
}

# Updates DNS at an amazon name server when using the Amazon Route53 DNS service
# requires WebService::Amazon::Route53 module
# call e.g. updateAmazon($publicIp, "my.example.com.");
# NOTE the dot at the end of the dns name (amazon record names end with a dot)
sub updateAmazon {
  my $myIp = shift;
  my $recName = shift;
  print "Updating Amazon with $myIp\n" unless $quiet;
  #use WebService::Amazon::Route53;
  my $r53 = WebService::Amazon::Route53->new(
    id => 'INSERT_ROUTE_53_ID_HERE',
    key => 'INSERT_ROUTE_53_API_KEY_HERE');
  my $zoneId = 'INSERT_ZONE_ID_HERE';
  my $recordSets = $r53->list_resource_record_sets(zone_id => $zoneId);
  updateAmazonRecord($recName, [$myIp], $recordSets, $zoneId, $r53);
}
sub updateAmazonRecord {
  my $recName = shift;
  my $newRecords = shift;
  my $recordSets = shift;
  my $zoneId = shift;
  my $r53 = shift;
  my $oldRecords;
  my $recTtl;
  my $recType;

  for my $record (@{$recordSets}) {
    my $name = $record->{name};
    if ($name eq $recName) {
      print "found record $name  \n" unless $quiet;
      $recType = $record->{type};
      $recTtl = $record->{ttl};
      $oldRecords = $record->{records};
      last;
    }
  }

  #use Data::Dumper;
  #print "record: $recName $recType $recTtl\n" unless $quiet;
  #print Dumper($oldRecords) unless $quiet;
  #print Dumper($newRecords) unless $quiet;

  my $cInfo = $r53->change_resource_record_sets(zone_id => $zoneId,
  changes => [
           {
               action => 'delete',
               name => $recName,
               type => $recType,
               ttl => $recTtl,
               records => $oldRecords
           },
           {
               action => 'create',
               name => $recName,
               type => $recType,
               ttl => $recTtl,
               records => $newRecords
           }
       ]);
  my $cInfoD = Dumper($cInfo);
  print "change info: \n$cInfoD\n" unless $quiet;

  my $errInfo = $r53->error;
  my $errInfoD = Dumper($errInfo);
  print "last error: \n$errInfoD\n" unless $quiet;
}


