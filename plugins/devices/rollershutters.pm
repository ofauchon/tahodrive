package plugins::devices::rollershutters;

use Data::Dump qw(dump);

use strict; 

my $PLUG_NAME="rollershutters";
my $PLUG_DESC="rollershutters device plugin";
my $PLUG_VERSION="0.1";


sub new {
  my $class = shift;
  my $self = {};
  return bless \$self, $class;
}

sub info {
	my $ret= "$PLUG_NAME: $PLUG_DESC version $PLUG_VERSION\n"; 
	return $ret; 
}

sub command {
	my ($obj, $id, $command, %p)=@_; 
	my $pVal=$p{"value"};
	my $pSpd=$p{"speed"};
	($id =~ /^io/) or die("Illegal device url:'$id'"); 
	($pVal>=0 && $pVal<=100) or die("Illegal value:'$pVal'"); 
	($pSpd eq "lowspeed") or die("Illegal speed:'$pSpd'"); 
	
	if ( $command eq "setClosureAndLinearSpeed" ){

		my $ret="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<applyRequest><actionGroup label=\"Device closure: $pVal% - AndroidPhone\">
<action deviceURL=\"".$id."\">
<command name=\"setClosureAndLinearSpeed\">
<parameter value=\"".$pVal."\" type=\"1\"/> 
<parameter value=\"".$pSpd."\" type=\"3\"/>
</command>
</action>
</actionGroup>
</applyRequest>"; 
		return $ret; 
		}
} #sub



