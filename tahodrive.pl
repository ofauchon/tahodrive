#!/usr/bin/perl

use XML::LibXML;
use LWP::UserAgent;
use Data::Dumper;
use Digest::MD5 qw(md5_hex); 
use Config::Simple;
use Getopt::Std;
use Module::Pluggable search_path => 'plugins::devices', sub_name => 'devices', instantiate => 'new'; 
use strict; 

# Save list of created plugin objects
my @plug_devices = devices(); 
my @values;

sub getPlugin{
	my $name=shift; 
	foreach my $p (@plug_devices) {
		if ($p =~/$name/i) {
			return $p; 
		} 
	}
	return '';
} 
	

my $URL="https://www.tahomalink.com/enduser-mobile-web/externalAPI";
my $AGENT="TaHoma/2.6 CFNetwork/672.0.8 Darwin/14.0.0";
my $REQUEST_TIMEOUT=15; 


# Default paths for configuration, logs, cache 
my $userdir=$ENV{HOME}."/.tahodrive";
my $userdircache=$ENV{HOME}."/.tahodrive/cache";
my $userdirlog=$ENV{HOME}."/.tahodrive/tahodrive.log";
my $userdirconf=$ENV{HOME}."/.tahodrive/tahodriverc";
(-d $userdir) or  mkdir($userdir, 0700) or die("Can't create $userdir"); ; 
(-d $userdircache) or  mkdir($userdircache, 0700) or die("Can't create $userdircache");

# Create template configuration if absent
if ( not -e $userdirconf) {
	my  $tmpcfg = new Config::Simple(syntax=>'ini');
	$tmpcfg->param('login.username', 'changeme');
	$tmpcfg->param('login.password', 'changeme');
	$tmpcfg->save($userdirconf) or die("Can't save configuration template $userdirconf"); 
	print("Configuration template created, please edit $userdirconf \n");
	exit; 
}

# Load configuration file 
my $cfg = new Config::Simple($userdirconf) or die Config::Simple->error();
my $USER=$cfg->param('login.username'); 
my $PASS=$cfg->param('login.password'); 
if ($USER eq "changeme" || $PASS eq "changeme") {print("Please edit $userdirconf, and change credentials before use \n"); exit();} 


# Some declarations  (user agent, xml parser) 
my $ua; 
my $parser;

my $g_gatewayId; 
my %options=();



# olog()
#
# Desc:     Append string to log file 
# Args:     logline: string to append to log file
# Return :  N/A
#
sub olog {
	my $logline = shift; 
	open ( FH , ">>", $userdirlog) or die ("Cannot open tahoma.log for append");
	print FH $logline."\n";
    close(FH);
}
# oend()
#
# Desc:     Ends program execution
# Args:     reason: reason for end 
# Return :  N/A
#
sub oend {
	my $reason = shift; 
	print("End: $reason\n"); 
	olog("End: $reason"); 
}

# request()
#
# Desc:     Send request to remote server
# Args:     url: Full url to contact
# Return :  xml document with response
#
sub request{
	my $u = shift; 
	my $p = shift; 
	my $doc; 
	my $cachefile=$userdircache."/".md5_hex($u); 
	#If cache enabled, and cache exists, use it ! 
	if (defined $options{c} && -e $cachefile ){
		#olog("Found $cachefile for query $u"); 
	#	print("! Using cache $cachefile for $u\n"); 
	} else {
		#olog("New cache $cachefile for $u\n"); 
		#print("New cache $cachefile for $u\n"); 
		my $res; 
		if (length($p) >0) {
			#print "Sending POST\n"; 
			$res = $ua->post($u, Content_Type => 'text/xml', Content => $p) or oend("POST Request $u failed");
		} else {
			#print "Sending GET\n"; 
			$res = $ua->get($u) or oend("GET Request $u failed");
		}
		open (FH, ">", $cachefile) or die("Can't create cache file $cachefile"); 
		print FH $res->content; 
		close (FH); 
	} 
	my $doc = $parser->load_xml( location => $cachefile );
	$doc->documentElement->namespaceURI;
	$doc->documentElement->setNamespaceDeclPrefix("", "gt");
	return $doc; 
}


#
# decodeSetup()
#
sub decodeSetup {
  my $xml = shift; 
  foreach my $gate ($xml->findnodes('/gt:setupResponse/gt:setup/gt:gateways/gt:gateway')) {
    print "  Gateway =>  id:".$gate->getAttribute('gatewayId')." functions:".$gate->getAttribute('functions')."\n";
	$g_gatewayId=$gate->getAttribute('gatewayId'); 
  }
  print("\n"); 
  foreach my $device ($xml->findnodes('//gt:devices/gt:device')) {
    print "  Device => label:'".$device->getAttribute('label')."' class:".$device->getAttribute('uiClass')." url:".$device->getAttribute('deviceURL')."\n";
  }
  print("\n"); 
}

# decodeHistory()
sub decodeHistory {
  my $xml = shift; 
  foreach my $exec ($xml->findnodes('/gt:historyResponse/gt:execution')) {
	my $date=$exec->getAttribute('startTime'); 
    my $formatted_time = scalar(localtime($date));
    print "  History execution =>  date:".$formatted_time." state:".$exec->getAttribute('state')." type:".$exec->getAttribute('type')."/". $exec->getAttribute('subType')." source:".$exec->getAttribute('source')."\n";
  	foreach my $command ($exec->findnodes('gt:command')) {
        print "        Command => device:" . $command->getAttribute('command');
        print " parameter:".$command->findnodes('gt:parameter')->get_node(0)->getAttribute('value')."\n";
    }
  }
  print("\n"); 
}
# decodeActionGroups()
sub decodeActionGroups {
  my $xml = shift; 
  foreach my $group ($xml->findnodes('/gt:actionGroupResponse/gt:actionGroup')) {
    print "  ActionGroup: oid:".$group->getAttribute('oid')." label:'".$group->getAttribute('label')."'\n";
    foreach my $action ($group->findnodes('gt:action')) {
        print "      Action => ".$action->getAttribute('deviceURL');
        print " command:".$action->findnodes('gt:command')->get_node(0)->getAttribute('name');
        print " parameter:".$action->findnodes('gt:command/gt:parameter')->get_node(0)->getAttribute('value')."\n";
    }
  }
}
# decodeEndUser()
sub decodeEndUser {
  my $xml = shift; 
  my $eu=$xml->findnodes('/gt:endUserResponse/gt:endUser')->get_node(0); 
  print "  EndUser => ".$eu->getAttribute('firstName').",".$eu->getAttribute('lastName')." templateName:". $eu->getAttribute('templateName')."\n";
}




##
## The real code starts here
##

# Command line options
getopts("hc", \%options);
if (defined $options{h}) {
  print "-h  This help\n" ;
  print "-c  Enable request cache (will cache all server responses, great for dev or demo)\n" ;
  exit; 
}

# Prepare LWP, xml parser
$ua = LWP::UserAgent->new();  
$ua->agent($AGENT);
$ua->timeout($REQUEST_TIMEOUT);
$ua->default_header('pragma' => "no-cache", 'max-age' => '0');
$ua->cookie_jar( {} );
$parser = XML::LibXML->new;

olog("Tahoma session start");

# Connect
my $xmlres=request($URL."/login?userId=".$USER."&userPassword=".$PASS);
my $ret=$xmlres->documentElement->getAttribute('success');
print("Authentication success: ".$ret."\n\n"); 
($ret eq "true") or oend("Authentication failed"); 

my $xmlres=request($URL."/getEndUser"); 
decodeEndUser($xmlres);

$xmlres=request($URL."/getSetup");
decodeSetup($xmlres);

$xmlres=request($URL."/getHistory");
decodeHistory($xmlres);

my $xmlres=request($URL."/getActionGroups"); 
decodeActionGroups($xmlres);

#my $xml = getPlugin("rollerShutter")->command("io://XXXX-XXXX-XXXX/XXXXXXXX", "setClosureAndLinearSpeed", (value => 10, speed => "lowspeed")); 
#my $xmlres=request($URL."/apply",$xml); 

# Clean shutdown with logout
my $xmlres=request($URL."/logout"); 

