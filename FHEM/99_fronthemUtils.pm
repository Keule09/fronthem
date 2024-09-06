##############################################
# $Id: 99_fronthemUtils.pm 0 2015-11-10 08:00:00Z herrmannj $
# modified: 2018-04-14 00:00:00Z raman
# modified: 2022-11-27 11:00:00Z alkazaa and wvhn
package main;

use strict;
use warnings;
use JSON;
use Time::HiRes qw(gettimeofday);

sub
fronthemUtils_Initialize($$)
{
  my ($hash) = @_;
}

sub fronthem_decodejson($) {
 return decode_json($_[0]);
}  

sub fronthem_encodejson($) {
 return encode_json($_[0]);
} 

sub
fronthem_ActualTimeStamp($)
{
	my ( $time ) = @_;	
	$time =  $time * 1000;
	return sprintf("%.0f", $time) * 1;
}

sub
fronthem_TimeStamp($)
{
  my ($date) = @_;
  my ($year,$mon,$mday,$hour,$min,$sec) = split(/[\s_:-]+/, $date);
  my $time = timelocal($sec,$min,$hour,$mday,$mon-1,$year);
  return $time * 1000;
}

# evaluates smartVISU duration format with up to 4 digits (instead of 2)
# loops through the parameter with more terms e.g. "1y 3m 5d 10h" and sum the results up
# Bonus: a leading term with 0 like e.g. "0w" will not contribute to the total time but it can
# be used to select the aggregation period for aggregation modes 'avg', 'min', 'sum' etc. in sub fronthem_Duration
sub
fronthem_Time($$)
{
	my ($time, $period) = @_;

	# allow Unix timestamp in milliseconds as well as "now"
	if ($period =~ /^(.*?)\s*(\d{13})/) { 
		return int($2/1000 + 0.5);
	}
	if ($period eq "now") {
		return $time;
	}	
	my @periods = split(' ', $period);  # split parameters like "1y 3m 5d 10h" into an array like ("1y","3m","5d","10h")
	foreach my $period (@periods) 	    # loop over the individual array elements
	{
		if ($period =~ /^([-+]?\d{1,4})(s|i|h|d|w|m|y)/)
		{
			my $newTime = 0;
			if ($2 eq "s")
			{
				$newTime = $1;
			}
			elsif ($2 eq "i")
			{
				$newTime = $1 * 60;
			}
			elsif ($2 eq "h")
			{
				$newTime = $1 * 3600;
			}
			elsif ($2 eq "d")
			{
				$newTime = $1 * 3600 * 24;
			}
			elsif ($2 eq "w")
			{
				$newTime = $1 * 3600 * 24 * 7;
			}
			elsif ($2 eq "m")
			{
				$newTime = $1 * 3600 * 24 * 30;
			}
			elsif ($2 eq "y")
			{
				$newTime = $1 * 3600 * 24 * 365;
			}
			$time -= $newTime;
		}
	}
	return $time;
}

# select the database evaluation mode from first term of smartVISU duration, e.g. "0d" is daystats but "1d" is hourstats
sub
fronthem_Duration($)    # hourstats daystats weekstats monthstats yearstats
{
	my ($duration) = @_;
	if ($duration =~ /^(\d{1,4})(s|i|h|d|w|m|y)/)
	{
		if ($2 eq "s" || $2 eq "i")
		{
			return "timerange";
		}
		elsif ($2 eq "h")
		{
			if ($1 eq "1") {
				return "timerange";
			}
			return "hourstats";
		}
		elsif ($2 eq "d")
		{
			if ($1 eq "1") {
				return "hourstats";
			}
			return "daystats";
		}
		elsif ($2 eq "w")
		{
			if ($1 eq "1") {
				return "daystats";
			}
			return "weekstats";
		}
		elsif ($2 eq "m")
		{
			if ($1 eq "1") {
				return "weekstats";
			}
			return "monthstats";
		}
		elsif ($2 eq "y")
		{
			if ($1 eq "1") {
				return "monthstats";
			}
			return "yearstats";
		}
	}	
	return "timerange";
}

###############################################################################
#
# Umsetzen der UZSU-Settings für ein device
#
###############################################################################
#
# Nicht vergessen! In FHEM notify definieren!
#
#    define UZSU notify .*:uzsu:.* { UZSU_execute($NAME, $EVTPART1) }
#
# oder wenn Einstellungen gespeichert werden sollen:
#
#    define UZSU notify .*:uzsu:.* { UZSU_execute($NAME, $EVTPART1, 'save') }
#
# und folgendes Attribut setzen:
#
#    attr global autosave 1
#
sub UZSU_execute($$;$)
{
	my ($device, $uzsu, $save) = @_;
	$uzsu = decode_json($uzsu);
	
	fhem('delete wdt_uzsu_'.$device.'.*');
	
	for (my $i = 0; $i < @{$uzsu->{list}}; $i++) {
		if ($uzsu->{list}[$i]->{active}) {
			my %rrule = UZSU_getRrules($uzsu->{list}[$i]{rrule});
			my $holiday = $uzsu->{list}[$i]{holiday}{weekend} && $uzsu->{list}[$i]{holiday}{workday} ? '' : $uzsu->{list}[$i]{holiday}{weekend} ? $rrule{'BYDAY'} ne '' ? ',$we' : '$we' : $uzsu->{list}[$i]{holiday}{workday} ? $rrule{'BYDAY'} ne '' ? ',!$we' : '!$we' : '';		
			my $time = $uzsu->{list}[$i]{event} eq "time" ?  $uzsu->{list}[$i]{time} : '{'.$uzsu->{list}[$i]->{event} .'_abs("REAL",' . $uzsu->{list}[$i]->{timeOffset} * 60 . ',' . ($uzsu->{list}[$i]->{timeMin} ne '' ? '"' . $uzsu->{list}[$i]->{timeMin} . '"' : '') . ',' . ($uzsu->{list}[$i]->{timeMax} ne '' ? '"' . $uzsu->{list}[$i]->{timeMax} . '"' : '') . ')}';	
			my $condition = UZSU_getCommand($uzsu->{list}[$i]{condition});
			
			my $weekdayTimer = $rrule{'BYDAY'} . $holiday . ($rrule{'BYDAY'} ne '' || $holiday ne '' ? "|" : '') . $time . "|" . $uzsu->{list}[$i]{value};	
			my $delayedExec = UZSU_getCommand($uzsu->{list}[$i]{delayedExec});
						
			fhem('defmod wdt_uzsu_' . $device . '_' . $i . ' WeekdayTimer ' . $device . ' en ' . $weekdayTimer . $condition);
			fhem('attr wdt_uzsu_' . $device . '_' . $i . ' room Automation->UZSU');
			fhem('attr wdt_uzsu_' . $device . '_' . $i . ' group ' . $device);
			fhem('setreading wdt_uzsu_' . $device . '_' . $i . ' weekdays ' . $weekdayTimer);
			fhem('defmod rg_uzsu_' . $device . ' readingsgroup wdt_uzsu_' . $device . '.*');
			fhem('attr rg_uzsu_' . $device . ' room UZSU');
			if ($delayedExec) {
				fhem('attr wdt_uzsu_' . $device . '_' . $i . ' delayedExecutionCond ' . $delayedExec);
			}
		}
	}
	if ($uzsu->{active}) {
		fhem('attr NAME=wdt_uzsu_' . $device . '_.*' . ' disable 0');
	}
	else {
		fhem('attr NAME=wdt_uzsu_' . $device . '_.*' . ' disable 1');
	}
	fhem('save', 1) if ($save eq 'save');	
}

###############################################################################
#
# UZSU-Hilfsfunktionen
#
###############################################################################
sub UZSU_getRrules($)
{
	my ($split) = @_; 
	my @a = split(/;/, $split);
	my %hash;
	foreach (@a){
		my ($key,$val) = split(/=/, $_);
		$hash{$key} = $val;
	}	
	return %hash;
}

sub UZSU_getCommand($)
{
	my ($command) = @_;	
	if($command->{active} && $command->{type} ne "String")  
	{
		if($command->{deviceString} =~ /^AttrVal|InternalVal|ReadingsVal\("\S+"\s?,\s?"\S+"\s?,\s?"\S*"\)$/)
		{
			return ' (' . $command->{deviceString} . ' ' . $command->{type} . ' "' . $command->{value} . '")';
		}
		elsif($command->{deviceString} =~ /^Value\("\S+"\)$/)
		{
			return ' (' . $command->{deviceString} . ' ' . $command->{type} . ' "' . $command->{value} . '")';
		}
	}
	elsif($command->{active} && $command->{type} eq "String" && $command->{deviceString} ne '')
	{
		if($command->{deviceString} =~ /^fhem ".+"( if\(.+\))?$/)
		{
			return ' {' . $command->{deviceString} . '}';
		}
		else
		{
			return ' (' . $command->{deviceString} . ')';
		}
	}
	else
	{
		return '';
	}
}


###############################################################################
#
# Sammeln der Log-Daten in einem Dummy-Device
# (Dummy-Device wir automatisch erstellt, wenn für zu überwachende Devices
#  svReadins gesetzt wird - Erklärung siehe unten!)
#
#
###############################################################################
#
# Nicht vergessen! In FHEM notify definieren!
#
# define Log notify .* { Log_SetList($NAME,$EVENT) }
#
# und folgende Attribute in "attr global userattr" hinzufügen:
#
# svEvents svReadins svRegex
#
# svReadins: Für das Device das Reading setzen, das überwacht werden soll.
#            z.B. wenn state überwacht werden soll:
#
#                 attr <device> svReadins state battery:Batterie
#
#            z.B. wenn state und battery überwacht und
#                 battery in Batterie geändert werden soll:
#
#                 attr <device> svReadins state battery:Batterie
#
#            Zur Übersicht der überwachten Devices kann eine readingsGroup 
#            angelegt werden:
#
#                 define rg_svLog readingsGroup <Name>,<svReadings> .*:?svReadins,?
#				  attr rg_svLog nameStyle style="color:red;;font-weight:bold"
#
# svEvents:  Wird automatisch für das Dummy-Device (Log-Liste) angelegt, kann aber
#            an die jeweiligen Bedürdnisse angepasst werden. 
#    
# svRegex:   Hier kann für das Dummy-Device (Log-Liste) eine Liste mit Events,
#            die ersetzt werden sollen, angegeben werden.
#
# 			 z.B. attr <device> svRegex low:schwach opened:geöffnet closed:geschlossen connected:verbunden disconnected:getrennt
#
sub
Log_SetList($$)
{
	my ($device, $event) = @_;
	my $reading = "";
    my $message = "";
		
	if ($event =~ qr/(.*?):\s+(.*)/p) {
		$reading = $1;
        $message = $2;
    } else {
        $reading = "state";
        $message = $event;
    }
	
	my @info = split(" ", AttrVal($device, "svReadins", ""));
	my $list = "";
	my $newReading = "";
	foreach (@info) {
		if ($_ =~ qr/(.*):(.+)/p) {
			$list = $1;
			$newReading = $2;
		} else {
			$list = $_;
		}
		
		if ($list eq $reading)
		{			
			fhem ("set" . " svLog_" . $list . " block");
			
			if ($newReading ne "") {
				$reading = $newReading;
			}

			if(!$defs{"svLog_" . $list}) {
				fhem ("define" . " svLog_" . $list . " dummy");
				fhem("attr" . " svLog_" . $list . " svEvents info:alive,ok,online,[O|o]pened,[C|c]onnected,[C|c]losed,[G|g]eschlossen warning:low,[O|o]pen,[O|o]ffen,offline,overload,unreachable error:dead,[D|d]isconnected,unknown,IOerr");
			}

			my @state = split(" ", AttrVal("svLog_" . $list, "svEvents", ""));
			foreach (@state) {
				if ($_ =~ qr/(.*):(.+)/p) {
					my $z = $2;
					$z =~ s/,/|/g;
									
					if($reading eq "state") {
						fhem ("setreading" . " svLog_" . $list . " " . $device . " " . $message);
					} elsif ($message =~ /.*:?\s?($z)/) {
						fhem ("setreading" . " svLog_" . $list . " " . $device . " " . $reading . " " . $1);
					} else {
						fhem ("setreading" . " svLog_" . $list . " " . $device . " " . $reading . " " . $message);
					}
				}
			}
			fhem ("set" . " svLog_" . $list . " send");			
		}	
	}
}

###############################################################################
#
# Log-Hilfsfunktionen
#
###############################################################################
sub
Log_GetList($)
{
	my ($name) = @_;
	my $list = "";
	my $level = "info"; # info = green, error = red,  warning = yellow (levels for smartvisu status.log)
		
	my @info = split(" ", AttrVal($name, "svRegex", ""));
	my @state = split(" ", AttrVal($name, "svEvents", ""));

	my $i = 1;
	foreach my $key (sort { $b cmp $a } keys %{$defs{$name}{READINGS}})
	{
		my $reading = $defs{$name}{READINGS}{$key}{VAL};
		
		foreach (@state) {
			if ($_ =~ qr/(.*):(.+)/p) {
				my $newLevel = $1;
				my $states = $2;
				$states =~ s/,/|/g;
				
				if($reading =~ /.*:?\s?($states)/)
				{
					$level = $newLevel;
							
					foreach (@info) {
						if ($_ =~ qr/(.*):(.+)/p) {
							my $a = $1;
							my $b = $2;	
							$reading =~ s/$a/$b/g;
						}
					}
				}
			}
		}
		
		my $device = AttrVal( $key, "alias", $key );
		my $timestring = $defs{$name}{READINGS}{$key}{TIME};
		$timestring =~ s/\s/T/g; # Compatibility for older Browser "2018-03-10T18:34:53"				
		$list .= '{"message":"'. $device . " - " . $reading . '","time":"' . $timestring . '","level":"' . $level . '"}' . ($i == keys(%{$defs{$name}{READINGS}}) ? "" : ",") if ($key ne "state");
			
		$i++;		
	}
	return $list;	
}


package fronthem;
use strict;
use warnings;

###############################################################################
# For use with UZSU-Widget in SV and UZSU-notify in fhem
# Setreading a device reading using JSON conversion (gadval => reading=decode_json() => setval => encode_json(reading) )
# the reading ("uzsu") must be created manually for each UZSU-enabled device in fhem using "setreading <device> uzsu {}"
# in the fhem commandline
###############################################################################

sub UZSU(@)
{
  my ($param) = @_;
  my $cmd = $param->{cmd};
  my $gad = $param->{gad};
  my $gadval = $param->{gadval};

  my $device = $param->{device};
  my $reading = $param->{reading};
  my $event = $param->{event};
  
  my @args = @{$param->{args}};
  my $cache = $param->{cache};

  if ($param->{cmd} eq 'get')
  {
    $param->{cmd} = 'send';
  }
  if ($param->{cmd} eq 'send')
  {
    $param->{gad} = $gad;
	$param->{gadval} = main::fronthem_decodejson(main::ReadingsVal($device, $reading, '{}'));
	$param->{gads} = [];
    return undef;
  }
  elsif ($param->{cmd} eq 'rcv')
  {
	$gadval = main::fronthem_encodejson($gadval);
	$gadval =~ s/;/;;/ig;
	$param->{result} = main::fhem("setreading $device $reading $gadval");
	$param->{results} = [];
    return 'done';
  }
  elsif ($param->{cmd} eq '?')
  {
    return 'usage: UZSU';
  }
  return undef;
}

###############################################################################
#
# connect fhem device with on|off state to switch
#
###############################################################################
sub AnAus(@)
{
  my ($param) = @_;
  my $cmd = $param->{cmd};
  my $gad = $param->{gad};
  my $gadval = $param->{gadval};

  my $device = $param->{device};
  my $reading = $param->{reading};
  my $event = $param->{event};
  
  my @args = @{$param->{args}};
  my $cache = $param->{cache};

  if ($param->{cmd} eq 'get')
  {
    $event = ($reading eq 'state')?main::Value($device):main::ReadingsVal($device, $reading, 'aus');
    $param->{cmd} = 'send';
  }
  if ($param->{cmd} eq 'send')
  {
    $param->{gad} = $gad;
		$param->{gadval} = (lc($event) eq 'an')?'1':'0';
		$param->{gads} = [];
    return undef;
  }
  elsif ($param->{cmd} eq 'rcv')
  {
		$param->{result} = ($gadval)?'an':'aus';
		$param->{results} = [];
    return undef;
  }
  elsif ($param->{cmd} eq '?')
  {
    return 'usage: AnAus';
  }
  return undef;
}

###############################################################################
#
# direct invert numerical values
# @param max 
#
###############################################################################
sub NumInvert(@)
{
  my ($param) = @_;
  my $cmd = $param->{cmd};
  my $gad = $param->{gad};
  my $gadval = $param->{gadval};

  my $device = $param->{device};
  my $reading = $param->{reading};
  my $event = $param->{event};
  
  my @args = @{$param->{args}};
  my $cache = $param->{cache};
  my $max = 100;
  if (defined($args[0])) 
  {
	$max = $args[0];
  }
 
  if ($param->{cmd} eq 'get')
  {
    $event = ($reading eq 'state')?main::Value($device):main::ReadingsVal($device, $reading, '');
    $param->{cmd} = 'send';
  }
  if ($param->{cmd} eq 'send')
  {
    return "NumInvert converter got [$event] from $device, $reading but cant interpret it as a number" unless $event =~ /\D*([+-]{0,1}\d+[.]{0,1}\d*).*?/;
	$event = $max - $1;
    $param->{gad} = $gad;
    $param->{gadval} = $event;
    $param->{gads} = [];
    return undef;
  }
  elsif ($param->{cmd} eq 'rcv')
  {	
	return "NumInvert converter received [$gadval] but cant interpret it as a number" unless $gadval =~ /\D*([+-]{0,1}\d+[.]{0,1}\d*).*?/;
    $gadval = $max - $1;
	$param->{result} = $gadval;
	$param->{results} = [];
    return undef;
  }
  elsif ($param->{cmd} eq '?')
  {
    return 'usage: NumInvert';
  }
  return undef;
}

###############################################################################
#
# Send readings collected in dummy device as status.log
#
###############################################################################
sub Log(@)
{
  my ($param) = @_;
  my $cmd = $param->{cmd};
  my $gad = $param->{gad};
  my $gadval = $param->{gadval};

  my $device = $param->{device};
  my $reading = $param->{reading};
  my $event = $param->{event};
  
  my @args = @{$param->{args}};
  my $cache = $param->{cache};

  if ($param->{cmd} eq 'get')
  {
    $param->{cmd} = 'send';
  }
  if ($param->{cmd} eq 'log')
  {
    $param->{cmd} = 'send';
  }
  if ($param->{cmd} eq 'send')
  {
	use Encode qw(decode encode);
	my $list = main::Log_GetList($device);
	$list = encode("utf8", '[' . $list . ']');
    $param->{gad} = $gad;	
	$param->{gadval} = main::fronthem_decodejson($list);
	$param->{gads} = [];

    return undef;
  }
  elsif ($param->{cmd} eq 'rcv')
  {
		$param->{result} = $gadval;
		$param->{results} = [];
    return undef;
  }
  elsif ($param->{cmd} eq '?')
  {
    return 'usage: log';
  }
  return undef;
}

###############################################################################
#
# Plot data from fhem database
# @param <name of database> 
#
###############################################################################
sub Plot(@)
{
  my ($param) = @_;
  my $cmd = $param->{cmd};
  my $gad = $param->{gad};
  my $gadval = $param->{gadval};

  my $device = $param->{device};
  my $reading = $param->{reading};
  my $event = $param->{event};
  
  my $mode = $param->{mode};
  my $start = $param->{start};
  my $end = $param->{end};
  my $count = $param->{count};
  my $interval = $param->{interval};
  my $updatemode = $param->{updatemode};
  
  my @args = @{$param->{args}};
  my $cache = $param->{cache};
     
  return "error $gad: converter syntax: missing paramter: name of database" if (@args != 1);
  
  if ($param->{cmd} eq 'get') {
    $param->{cmd} = 'send';
  }
  if ($param->{cmd} eq 'plot') {
    $param->{cmd} = 'send';
  }
  if ($param->{cmd} eq 'send') {
		my @data = {
			"item" => $gad . '.' . $mode . '.' . $start . '.' . $end  . '.' . $count,
			"updatemode" => $updatemode,
			"plotdata" => [],
		};
			
		if ($updatemode eq 'point') {
			if ($mode eq "raw") {
				push(@{$data[0]->{plotdata}[0]},  main::fronthem_ActualTimeStamp(main::gettimeofday()));
				push(@{$data[0]->{plotdata}[0]}, sprintf("%#.4f", $event) * 1);
			}						
			elsif ($mode eq "avg") {
				
			}
			elsif ($mode eq "sum") {
				
			}
			elsif ($mode eq "min") {
				
			}
			elsif ($mode eq "max") {
				
			}
		}
		else {			
			my $from = main::FmtDateTime(main::fronthem_Time(time(), $start));
			$from =~ s/ /_/ig;
			my $to = main::FmtDateTime(main::fronthem_Time(time(), $end));			
			$to =~ s/ /_/ig;
		
			my $duration = "timerange";
			if ($mode ne "raw") {
				$duration = main::fronthem_Duration($start);
			}
				
			my $string = main::CommandGet(undef, $args[0] . ' - webchart ' . $from . ' ' . $to . ' ' . $device . ' ' . $duration . ' TIMESTAMP ' . $reading);
			my @response = main::fronthem_decodejson($string);

			foreach my $data (@response) {
				my $i = 0;
				foreach my $row (@{$data->{data}}) {
					if ($mode eq "raw") { # [TIMESTAMP,VALUE]
						push(@{$data[0]->{plotdata}[$i]}, main::fronthem_TimeStamp($row->{TIMESTAMP}));
						push(@{$data[0]->{plotdata}[$i]}, sprintf("%#.4f", $row->{VALUE}) * 1);
					}
					elsif ($mode eq "avg") { # [TIMESTAMP,AVG]
						push(@{$data[0]->{plotdata}[$i]}, main::fronthem_TimeStamp($row->{TIMESTAMP}));
						push(@{$data[0]->{plotdata}[$i]}, $duration eq "timerange" ? sprintf("%#.4f", $row->{VALUE}) * 1 : sprintf("%#.4f", $row->{AVG}) * 1);
					}
					elsif ($mode eq "sum") { # [TIMESTAMP,SUM]
						push(@{$data[0]->{plotdata}[$i]}, main::fronthem_TimeStamp($row->{TIMESTAMP}));
						push(@{$data[0]->{plotdata}[$i]}, $duration eq "timerange" ? sprintf("%#.4f", $row->{VALUE}) * 1 : sprintf("%#.4f", $row->{SUM}) * 1);
					}
					elsif ($mode eq "min") { # [TIMESTAMP,MIN]
						push(@{$data[0]->{plotdata}[$i]}, main::fronthem_TimeStamp($row->{TIMESTAMP}));
						push(@{$data[0]->{plotdata}[$i]}, $duration eq "timerange" ? sprintf("%#.4f", $row->{VALUE}) * 1 : sprintf("%#.4f", $row->{MIN}) * 1);
					}
					elsif ($mode eq "max") {  # [TIMESTAMP,MAX]
						push(@{$data[0]->{plotdata}[$i]}, main::fronthem_TimeStamp($row->{TIMESTAMP}));
						push(@{$data[0]->{plotdata}[$i]}, $duration eq "timerange" ? sprintf("%#.4f", $row->{VALUE}) * 1 : sprintf("%#.4f", $row->{MAX}) * 1);
					}
					$i++;
				}
			}
		}	
		$param->{gads} = [@data];
		return undef;
  }
  elsif ($param->{cmd} eq 'rcv') {
	$param->{result} = $gadval;
	$param->{results} = [];
	return undef;
  }
  elsif ($param->{cmd} eq '?') {
	return 'usage: plot';
  }
  return undef;
}

###############################################################################
#
# Plot data from fhem filelog
# @param <name of logfile> <column> <regex>
#
###############################################################################
sub Plotfile(@)
{
  my ($param) = @_;
  my $cmd = $param->{cmd};
  my $gad = $param->{gad};
  my $gadval = $param->{gadval};

  my $device = $param->{device};
  my $reading = $param->{reading};
  my $event = $param->{event};
  
  my $mode = $param->{mode};
  my $start = $param->{start};
  my $end = $param->{end};
  my $count = $param->{count};
  my $interval = $param->{interval};
  my $updatemode = $param->{updatemode};
  
  my @args = @{$param->{args}};
  my $cache = $param->{cache};
     
  return "error $gad: converter syntax: missing paramter: name of database" if (@args < 1 || @args > 4);
 
  if ($param->{cmd} eq 'get') {
    $param->{cmd} = 'send';
  }
  if ($param->{cmd} eq 'plot') {
    $param->{cmd} = 'send';
  }
  if ($param->{cmd} eq 'send') {
	my @data = {
			"item" => $gad . '.' . $mode . '.' . $start . '.' . $end  . '.' . $count,
			"updatemode" => $updatemode,
			"plotdata" => [],
	};
	
	my $column = 3;
	if ($reading eq "state") {
		$reading = "";
	} elsif($reading ne "state" && @args == 1) {
		$column = 4;
	} elsif(@args > 1) { 
		$column = $args[1] * 1;
		if ($args[2]) {
			$reading = $args[2];
		}
	}	
	my $regex = $args[3] ? $args[3] : "";
		
		if ($updatemode eq 'point') {
			if (!$args[3]) {
				push(@{$data[0]->{plotdata}[0]},  main::fronthem_ActualTimeStamp(main::gettimeofday()));
				push(@{$data[0]->{plotdata}[0]}, sprintf("%#.4f", $event) * 1);
			}
		}
		else {
			my $from = main::FmtDateTime(main::fronthem_Time(time(), $start));
			$from =~ s/ /_/ig;
			my $to = main::FmtDateTime(main::fronthem_Time(time(), $end));			
			$to =~ s/ /_/ig;
			
			my $string = main::fhem("get "  . $args[0] . " - - " . $from . " " . $to ." " . $column .":" . $reading . ":0:" . $regex, 1);
			my @response = split("\n", $string);
			pop @response;
			
			for (my $i = 0; $i < @response; $i++) {			
				$response[$i] =~ /([0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}:[0-9]{2}:[0-9]{2})\s+([0-9\.-]+)/;				
				push(@{$data[0]->{plotdata}[$i]}, main::fronthem_TimeStamp($1));
				push(@{$data[0]->{plotdata}[$i]}, sprintf("%#.4f", $2) * 1);
			}
		}	
		$param->{gads} = [@data];
		return undef;
  }
  elsif ($param->{cmd} eq 'rcv') {
	$param->{result} = $gadval;
	$param->{results} = [];
	return undef;
  }
  elsif ($param->{cmd} eq '?') {
	return 'usage: plotfile';
  }
  return undef;
}

1;

=pod
=begin html

<a name="fronthemUtils"></a>
<h3>fronthemUtils</h3>
<ul>
</ul>
=end html
=cut
