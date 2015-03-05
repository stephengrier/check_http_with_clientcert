#!/usr/bin/perl -w
###################################################################################
# check_http_with_clientcert - Nagios plugin to test a HTTP service using an SSL
# client certificate. At the time of writing this functionality is not available
# in the standard check_http plugin.
# This plugin will assume the use of HTTPS (SSL) because you wouldn't be using
# a client certificate otherwise. You can specify the client certificate file to
# use with the --clientcert option, and the private key using the --private-key.
# NB: if you need to send the CA certificate chain along with the client cert, this
# is possible by placing all certs in the same file as the client cert. All certs
# should be in PEM format. You may need specific versions of certain perl modules
# (e.g. Net/HTTP, LWP) for this plugin to work correctly. If so these can be
# installed into /usr/local/check_http_with_clientcert.
#
# Stephen Grier <s.grier at ucl.ac.uk>, Mar 2015.
###################################################################################
use lib '/usr/local/check_http_with_clientcert/lib';
use strict;
use LWP::UserAgent;
use Data::Dumper;
use Getopt::Long;

# Nagios exit codes.
my $nag_exit_codes = {'OK' => 0, 'WARNING' => 1, 'CRITICAL' => 2};

my ($verbose,$host,$port,$use_ssl,$uri,$clientCertFile,$keyFile,
    $caCertFile,$verify_hostname,$expectResponseCode,$expectString,
    $timeout);

my $usage = "Usage:
$0 -H host --clientcert=/path/to/cert --private-key=/path/to/key <-v> <-p port> <-S> <-u uri> \
  <--CAfile=/path/to/CAfile> <-e expected RC> <-V bool> <-e code> <-s expected string> <-t secs>
Options:
  -v --verbose      - Verbose
  -H --host         - Host to connect to
  -p --port         - Port (default 443)
  -S --ssl          - Use HTTPS
  -u --uri          - URI (default /)
     --clientcert   - file containing the client certificate in PEM format
     --private-key  - file containing the private key for the clientcert
     --CAfile       - File containing the CA certificate(s) for the server cert
  -V --verify_hostname - Check the server certificate matches the expected hostname (default true)
  -e --expect-rc    - The expected HTTP response code (default 200)
  -s --string       - String to expect in the HTTP body
  -t --timeout      - Timout in seconds (default 10)
";

GetOptions (
  "verbose|v" => \$verbose,
  "host|H=s"   => \$host,
  "port|p=s"   => \$port,
  "ssl|S" => \$use_ssl,
  "uri|u=s" => \$uri,
  "clientcert=s" => \$clientCertFile,
  "private-key|K=s" => \$keyFile,
  "CAfile=s" => \$caCertFile,
  "verify_hostname=i" => \$verify_hostname,
  "expect-rc|e=s" => \$expectResponseCode,
  "string=s" => \$expectString,
  "timeout|t=i" => \$timeout,
) or die($usage);

# Sanity.
if (!$host) {die $usage;}

$uri = '/' if (!$uri);
$port = '443' if (!$port);
$expectResponseCode = '200' if (!$expectResponseCode);
$use_ssl = 1 if (!$use_ssl);
$verify_hostname = 1 if (!defined($verify_hostname));

# Build a URL string from the constituent parts.
my $full_url = sprintf("%s%s:%s%s",
                       ($use_ssl) ? 'https://' : 'http://',
                       $host,
                       $port,
                       $uri );

print "Requesting $full_url using client certificate...\n" if ($verbose);
 
# Init a user agent file handle.
# Prime it with our client certificate + private key.
my $ua = LWP::UserAgent->new(
    ssl_opts => {
        verify_hostname => $verify_hostname,
        SSL_use_cert => 1,
        SSL_cert_file   => $clientCertFile,
        SSL_key_file    => $keyFile,
        SSL_ca_file     => $caCertFile,
    },
    timeout => $timeout,
);

# Make our HTTP request.
my $response = $ua->get($full_url);

# If the HTTP request failed $response->is_success will be false.
if (!$response->is_success) {
  print "HTTP CRITICAL - ".$response->status_line."\n";
  exit $nag_exit_codes->{'CRITICAL'};
}

#print Dumper($response);

# Check the HTTP response code matches what we expect.
if ($response->code ne $expectResponseCode) {
  print "HTTP CRITICAL - expected HTTP code $expectResponseCode but actually got ".$response->code."\n";
  exit $nag_exit_codes->{'CRITICAL'};
}
print "Got expected HTTP code ".$response->code."\n" if ($verbose);

# If --string was specified, check the HTTP body contains the string.
if ($expectString) {
  my $body = $response->decoded_content();
  if ($body !~ /$expectString/) {
    print "HTTP CRITICAL - HTTP response did not contain expected string $expectString\n";
    exit $nag_exit_codes->{'CRITICAL'};
  }
  print "HTTP body did contain expected string $expectString\n" if ($verbose);
}

# All good.
print "HTTP OK: ".$response->status_line."\n";
exit $nag_exit_codes->{'OK'};

