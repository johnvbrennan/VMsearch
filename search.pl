#!/usr/bin/perl
# File: search.pl
# Author: John Brennan
# Date: 02-May-2013
# Description: Searches for virtual machines matching all of the parameters specified.
#
use strict;
use warnings;
use VMware::VIRuntime;
use VMware::VILib;

#
# Define the options/input parameters that the script will accept
#
my %opts = (
	ip => 
	{
		type => "=s", 
		help => "The IP address to search for, in format xxx.xxx.xxx.xxx",
		require => 0
	},
	mac => 
	{
		type => "=s", 
		help => "The MAC address to search for.",
		require => 0
	},
	"cdrom-connected" => 
	{
		type => "!", 
		help => "Has VM a cd-rom connected to it.",
		require => 0
	},
	"no--cdrom-connected" => 
	{
		type => "!", 
		help => "Has VM no cd-rom connected to it.",
		require => 0
	},
	"cdrom-iso" => 
	{
		type => "=s", 
		help => "The path to the ISO image to look for.",
		require => 0
	},
	vm => 
	{
		type => "=s", 
		help => "The name of the virtual machine to search for.",
		require => 0
	},
	vmserver => 
	{
		type => "=s", 
		help => "The name of the host that the VM is running on.",
		require => 0
	},
	datastore => 
	{
		type => "=s", 
		help => "The name of the datastore to search for.",
		require => 0
	},
	network => 
	{
		type => "=s", 
		help => "The name of the network to search for.",
		require => 0
	},
	"network-connected" => 
	{
		type => "!", 
		help => "Device is connected to the network",
		require => 0
	},
	"no--network-connected" => 
	{
		type => "!", 
		help => "Device is connected to the network",
		require => 0
	},
	"scsi-type" => 
	{
		type => "=s", 
		help => "The type of SCSI adapter used by the virtual machine. (ParaVirtualSCSIController, VirtualBusLogicController, VirtualLsiLogicController, VirtualLsiLogicSASController)",
		require => 0
	},
	"net-type" => 
	{
		type => "=s", 
		help => "The type of network controller used by the virtual machine. (VirtualVmxnet2, VirtualVmxnet3, VirtualPCNet32, VirtualE1000e, VirtualE1000)",
		require => 0
	},	
	power => 
	{
		type => "=s", 
		help => "The current power state of the virtual machine. (PoweredOff, PoweredOn, Suspended)",
		require => 0
	},			
);

Opts::add_options(%opts);


# Parse and validate input parameters
Opts::parse();
Opts::validate();

#
# Custom validation of the value for specific parameters. If an invalid option is specified
# for a parameter we call die which will write to STDERR and exit the application.
#
my %powerOptions = ('poweredOn' => 'poweredOn', 
					'poweredOff' => 'poweredOff', 
					'suspended' => 'suspended');
my %scsiTypeOptions = ('ParaVirtualSCSIController' => 'ParaVirtualSCSIController',
						'VirtualBusLogicController' => 'VirtualBusLogicController', 
						'VirtualLsiLogicController' => 'VirtualLsiLogicController',
						'VirtualLsiLogicSASController' => 'VirtualLsiLogicSASController');
my %netTypeOptions = ('VirtualVmxnet2' => 'VirtualVmxnet2', 
						'VirtualVmxnet3' => 'VirtualVmxnet3', 
						'VirtualPCNet32' => 'VirtualPCNet32', 
						'VirtualE1000e'  => 'VirtualE1000e', 
						'VirtualE1000'   => 'VirtualE1000');

die ("Invalid setting for 'power'. Valid options are: poweredOn, poweredOff or suspended.\n")
     if ((Opts::option_is_set ('power')) && (! exists ($powerOptions{Opts::get_option('power')})));

die ("Invalid setting for 'scsi-type'. Valid options are: ParaVirtualSCSIController, VirtualBusLogicController, VirtualLsiLogicController or VirtualLsiLogicSASController.\n")
     if ((Opts::option_is_set ('scsi-type')) && (! exists ($scsiTypeOptions {Opts::get_option('scsi-type')})));

die ("Invalid setting for 'net-type'. Valid options are: VirtualVmxnet2, VirtualVmxnet3, VirtualPCNet32, VirtualE1000e or VirtualE1000.\n")
     if ((Opts::option_is_set ('net-type')) && (! exists ($netTypeOptions{Opts::get_option('net-type')})));

# All inputs have been validated so connect to the ESXi/vCenter server	 
Util::connect();

# 
# Create an inititial filter to pass to find_entity_views. If vm or power inputs are not 
# supplied then the filter will be empty and all VM's will be returned.
#
my $searchFilter = CreateSimpleSearchFilter(Opts::option_is_set('vm') ? Opts::get_option('vm') : undef, 	# vm			
					   Opts::option_is_set('power') ? $powerOptions{Opts::get_option('power')} : undef);	# power										

#
# Execute query and iterate over each result/virtual machine returned 
# We need to perform additional filtering for the "complex" types that can't be filtered
# and require manual inspection of each property on the virtual machine.
#
foreach my $vm (@{Vim::find_entity_views(view_type => 'VirtualMachine', filter => $searchFilter, properties => ['name','config','guest','summary'])})
{
	#
	# Check each filter that was specified on the command line. If any filter fails
	# to find a match then the loop will jump to the next virtual machine in the 
	# result set and will not print the name and mo_ref of the VM.
	#
	if(
		(Opts::option_is_set('ip') && (!SearchForIP($vm, Opts::get_option('ip')))) ||
		(Opts::option_is_set('mac') && (!SearchForMac($vm, Opts::get_option('mac')))) ||
		(Opts::option_is_set('scsi-type') && (!SearchForScsiType($vm, Opts::get_option('scsi-type')))) ||
		(Opts::option_is_set('network-connected') && (!SearchForNetworkConnected($vm, 1))) ||
		(Opts::option_is_set('no--network-connected') && (!SearchForNetworkConnected($vm, 0))) ||
		(Opts::option_is_set('network') && (!SearchForNetworkName($vm, Opts::get_option('network')))) ||
		(Opts::option_is_set('net-type') && (!SearchForNetworkControllerType($vm, Opts::get_option('net-type')))) ||
		(Opts::option_is_set('cdrom-connected') && (!SearchForCdromConnected($vm, 1))) ||
		(Opts::option_is_set('no--cdrom-connected') && (!SearchForCdromConnected($vm, 0))) ||
		(Opts::option_is_set('cdrom-iso') && (!SearchForCdromIso($vm, Opts::get_option('cdrom-iso')))) ||
		(Opts::option_is_set('vmserver') && (!SearchForEsxHost($vm, Opts::get_option('vmserver')))) ||
    		(Opts::option_is_set('datastore') && (!SearchForDataStore($vm, Opts::get_option('datastore'))))
	)
    	{		
		# VM does not match, Jump to the next virtual machine in the result set.
		next;		
	}
	
	#	
	# If code execution gets to here then the virtual machine has successfully 
	# passed all of the search filters above and is a valid result. Print the details
	# of this VM to the screen.
	#
	print $vm->name, "\t", $vm->{'mo_ref'}->value, "\n";
}

# Disconnect from the server
Util::disconnect();

#
# Description: Returns true if a match is found for the ip address and false otherwise
#
# $virtualMachine	= a reference to the virtual machine to inspect
# $ipAddressToMatch	= the ip address to match on
#
sub SearchForIP
{
	my($virtualMachine, $ipAddressToMatch) = @_;

	my $matchFoundForIP = 0;
	
	#
	# The IP can only be checked if the VMware tools are installed.
	#
	if($virtualMachine->guest->toolsStatus->val eq "toolsOk")
	{					
		#
		# Enumerate over each NIC and see if it has an IP Address that matches
		#
		foreach my $nic(@{$virtualMachine->guest->net})
		{
			#
			# Within each NIC we inspect the ipConfig->ipAddress property/array
			#
			foreach my $ipConfig(@{$nic->ipConfig->ipAddress})
			{
				if($ipConfig->ipAddress eq $ipAddressToMatch)
				{
					# print $virtualMachine->name, ". IP matched: ", $ipConfig->ipAddress, "\n";
					$matchFoundForIP = 1;
					last;
				}
			}
		}
	}
	
	return $matchFoundForIP;
}

#
# Description: Returns true a Virtual Machine is running on the ESX host specified.
#
# $virtualMachine	= a reference to the virtual machine to inspect
# $esxHostToMatch	= the name of the ESX host to match on e.g. ESXi-1.vmeduc.com
#
sub SearchForEsxHost
{
	my($virtualMachine, $esxHostToMatch) = @_;

	my $matchFoundForEsxHost = 0;
	my $hostMoRef = $$virtualMachine{summary}{runtime}{host};
	
	if(!defined($hostMoRef))
	{
		print STDERR "unable to get moRef to host!";
	}
	else
	{
		# Use the properties hash to reduce the size of the object returned.
		my $host = Vim::get_view(mo_ref=>$hostMoRef, properties => ['name']);
		
		if($host->name eq $esxHostToMatch)
		{
			#print $virtualMachine->name, ". ESX host matched: ", $host->name,  "\n";
			$matchFoundForEsxHost= 1;
		}
	}
	return $matchFoundForEsxHost;
}

#
# Description: Returns true if a match is found for the MAC address and false otherwise
#
# $virtualMachine	= a reference to the virtual machine to inspect
# $macAddressToMatch	= the MAC address to match on
#
sub SearchForMac
{
	my($virtualMachine, $macAddressToMatch) = @_;

	my $matchFoundForMac = 0;

	foreach my $device(@{$virtualMachine->config->hardware->device})
	{
		#
		# Only devices that are a type of Virtual Network Card will be inspected
		#
		if( ($device->isa('VirtualVmxnet2') || 
		$device->isa('VirtualVmxnet3') || 
		$device->isa('VirtualPCNet32') || 
		$device->isa('VirtualE1000e') || 
		$device->isa('VirtualE1000')) && $device->macAddress eq $macAddressToMatch)
		{
			# print $virtualMachine->name, ". MAC matched: ", $nic->macAddress, "\n";
			$matchFoundForMac = 1;
			last;
		}		
	}

	return $matchFoundForMac;
}

#
# Description: Returns true if a match is found for the network name on any of the virtual NICs
#		 attached to the virtual machine and false otherwise.
#
# $virtualMachine		= a reference to the virtual machine to inspect
# $networkNameToMatch	= the network name to match on
#
sub SearchForNetworkName
{
	my($virtualMachine, $networkNameToMatch) = @_;

	my $matchFoundForNetworkName = 0;

	foreach my $device(@{$virtualMachine->config->hardware->device})
	{
		#
		# Only devices that are a type of Virtual Network Card will be inspected
		#
		if( ($device->isa('VirtualVmxnet2') || 
		$device->isa('VirtualVmxnet3') || 
		$device->isa('VirtualPCNet32') || 
		$device->isa('VirtualE1000e') || 
		$device->isa('VirtualE1000')))
		{			
			my $networkMoRef = $$device{backing}{network};
		
			if(!defined($networkMoRef))
			{
				print STDERR "unable to get moRef to network!";
			}
			else
			{
				# Use the properties hash to reduce the size of the object returned.
				my $network = Vim::get_view(mo_ref=>$networkMoRef, properties => ['name']);
		
				if($network->name eq $networkNameToMatch)
				{
					#print $virtualMachine->name, ". Network name matched: ", $network->name,  "\n";
					$matchFoundForNetworkName = 1;
					last;
				}
			}			
		}
	}
	
	return $matchFoundForNetworkName;
}

#
# Description: Returns true if a match is found for the SCSI type and false otherwise.
#
# $virtualMachine	= a reference to the virtual machine to inspect
# $scsiTypeToMatch	= the scsi type to match on
#
sub SearchForScsiType
{
	my($virtualMachine, $scsiTypeToMatch) = @_;

	my $matchFoundForScsiType = 0;
		
	foreach my $device(@{$virtualMachine->config->hardware->device})
	{
		if($device->isa($scsiTypeToMatch))
		{
			# print $virtualMachine->name, ". SCSI type matched: ", $scsiTypeToMatch, "\n";
			$matchFoundForScsiType = 1;
			last;
		}		
	}

	return $matchFoundForScsiType;
}

#
# Description: Returns true if the network controller is one of the following types:
#		{VirtualPCNet32,VirtualVmxnet2,VirtualVmxnet3,VirtualE1000, VirtualE1000e}
#		 Otherwise returns false.
#
# $virtualMachine				= a reference to the virtual machine to inspect
# $networkControllerTypeToMatch	= the type of the network controller to match on
#
sub SearchForNetworkControllerType
{
	my($virtualMachine, $networkControllerTypeToMatch) = @_;

	my $matchFoundForNetworkControllerType = 0;

	foreach my $device(@{$virtualMachine->config->hardware->device})
	{
		if($device->isa($networkControllerTypeToMatch))
		{
			# print $virtualMachine->name, ". Network controller type matched: ", $networkControllerTypeToMatch,  "\n";
			$matchFoundForNetworkControllerType = 1;
			last;
		}
	}

	return $matchFoundForNetworkControllerType;
}

#
# Description: Returns true if a match is found for the virtual machine has a NIC that is
#		 connected/not connected and false otherwise. The $deviceStatus indicates the connected 
#		 status that we are searching for i.e. connected or not connected.
#
# $virtualMachine	= a reference to the virtual machine to inspect
# $deviceStatus	= the device is connected/not connected. 1= connected, 0 = not connected
sub SearchForNetworkConnected
{
	my($virtualMachine, $deviceStatus) = @_;

	my $matchFoundForNetworkConnected = 0;
		
	foreach my $device(@{$virtualMachine->config->hardware->device})
	{
		if(($device->isa('VirtualPCNet32')	|| 
		$device->isa('VirtualVmxnet2') 	|| 
		$device->isa('VirtualVmxnet3') 	|| 
		$device->isa('VirtualE1000')   	|| 
		$device->isa('VirtualE1000e')) && $device->connectable->connected == $deviceStatus)
		{		
			# print $virtualMachine->name, ". Network connected match: ", $device->connectable->connected, "\n";		 
			$matchFoundForNetworkConnected = 1;
			last;
		}
	}

	return $matchFoundForNetworkConnected;
}

#
# Description: Returns true if a match is found for the virtual machine has a VirtualCdrom that is
#		 connected/not connected and false otherwise. The $deviceStatus indicates the connected 
#		 status that we are searching for i.e. connected or not connected.
#
# $virtualMachine	= a reference to the virtual machine to inspect
# $deviceStatus      = the device is connected/not connected. 1 = connected, 0 = not connected
# 
sub SearchForCdromConnected
{
	my($virtualMachine, $deviceStatus) = @_;

	my $matchFoundForCdromConnected = 0;
			
	foreach my $device(@{$virtualMachine->config->hardware->device})
	{
		if($device->isa('VirtualCdrom') && $device->connectable->connected == $deviceStatus)
		{
			# print "Device status: ", $device->connectable->connected, "\n";

			# print $virtualMachine->name, ". CDROM connected match.\n";
			$matchFoundForCdromConnected = 1;
			last;
		} 
	} 

	return $matchFoundForCdromConnected;
} 

#
# Description: Returns true if a match is found for the virtual machine uses the datastore 
#		 specified and false otherwise. String comparison is case sensitive.
#
# $virtualMachine	= a reference to the virtual machine to inspect
# $datastoreToMatch  = the name of the datastore to match
#
sub SearchForDataStore
{
	my($virtualMachine, $datastoreToMatch) = @_;

	my $matchFoundForDataStore = 0;
			
	foreach my $device(@{$virtualMachine->config->datastoreUrl})
	{
		if($device->name eq $datastoreToMatch)
		{
			# print $device->name, ". Datastore match.\n";
			$matchFoundForDataStore = 1;
			last;
		} 
	} 

	return $matchFoundForDataStore;
}

#
# Description: Returns true if a match is found for the virtual machine that has
#		 a VirtualCdrom and the ISO filename matches the regular expression.
#
# $virtualMachine	= a reference to the virtual machine to inspect.
# isoRegexToMatch 	= a regular expression pattern to match against.
#
sub SearchForCdromIso
{
	my($virtualMachine, $isoRegexToMatch) = @_;

	my $matchFoundForCdromIso = 0;
	
	#
	# Iterate over each device on the VM. If the device is VirtualCdRom then
	# examine the backing->fileName property. backing object is of type VirtualCdromIsoBackingInfo
	# The backing object will differ based on whether there is an ISO image used or a physical cdrom from host etc.
	#
	foreach my $device(@{$virtualMachine->config->hardware->device})
	{
		if($device->isa('VirtualCdrom') && $device->backing->isa('VirtualCdromIsoBackingInfo') && $device->backing->fileName =~ $isoRegexToMatch)
		{
			# print $virtualMachine->name, ". ", $device->backing->fileName, ". ISO name matched\n";
			$matchFoundForCdromIso = 1;
			last;
		} 
	}
	return $matchFoundForCdromIso;
}		
		
#######################################################################################
#
# Description:  takes a set of search criteria and builds a hash that can be
#				passed to the find_entity_views.
# $virtualMachineName 	= the name of the virtual machine
# $powerState			= the power status of the device
# 
#
sub CreateSimpleSearchFilter
{
	my($virtualMachineName, $powerState) = @_;
	
	my %searchFilter = ();

	if(defined $virtualMachineName)
	{
		# Name: $virtualMachineName. Case insensitive search
		$searchFilter{'name'} = qr/$virtualMachineName/;
	}
	
	if(defined $powerState)
	{
		# Name: $powerState
		$searchFilter{'runtime.powerState'} = $powerState;
	} 
	
	# return a reference to the hash
	return \%searchFilter;
}