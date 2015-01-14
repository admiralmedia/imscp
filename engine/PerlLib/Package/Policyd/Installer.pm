#!/usr/bin/perl

=head1 NAME

Package::Policyd::Installer - i-MSCP Policyd Weight configurator installer

=cut

# i-MSCP - internet Multi Server Control Panel
# Copyright (C) 2010-2015 by internet Multi Server Control Panel
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# @category    i-MSCP
# @copyright   2010-2015 by i-MSCP | http://i-mscp.net
# @author      Daniel Andreca <sci2tech@gmail.com>
# @author      Laurent Declercq <l.declercq@nuxwin.com>
# @link        http://i-mscp.net i-MSCP Home Site
# @license     http://www.gnu.org/licenses/gpl-2.0.html GPL v2

package Package::Policyd::Installer;

use strict;
use warnings;

no if $] >= 5.017011, warnings => 'experimental::smartmatch';

use iMSCP::Debug;
use iMSCP::Config;
use File::Basename;
use iMSCP::File;
use iMSCP::Execute;
use parent 'Common::SingletonClass';

=head1 DESCRIPTION

 This is the installer for the Policyd Weight configurator package.

 See Package::Policyd for more information.

=head1 PUBLIC METHODS

=over 4

=item registerSetupListeners(\%eventManager)

 Register setup event listeners

 Param iMSCP::EventManager \%eventManager
 Return int 0 on success, other on failure

=cut

sub registerSetupListeners
{
	my ($self, $eventManager) = @_;

	$eventManager->register('beforeSetupDialog', sub { push @{$_[0]}, sub { $self->showDialog(@_) }; 0; });
}

=item showDialog(\%dialog)

 Show dialog

 Param iMSCP::Dialog \%dialog
 Return int 0 or 30;

=cut

sub showDialog
{
	my ($self, $dialog, $rs) = (shift, shift, 0);
	my $dnsblCheckOnly = main::setupGetQuestion('DNSBL_CHECKS_ONLY') || $self->{'config'}->{'DNSBL_CHECKS_ONLY'} ||  '';

	$dnsblCheckOnly = lc($dnsblCheckOnly);

	if($main::reconfigure ~~ ['mailfilters', 'all', 'forced'] || not $dnsblCheckOnly ~~ ['yes', 'no']) {
		($rs, $dnsblCheckOnly) = $dialog->radiolist(
"
\\Z4\\Zb\\Zui-MSCP Policyd Weight Package\\Zn

Do you want to disable additional checks for MTA, HELO and domain?\n

\\Z1Yes\\Zn: (may cause some spam messages to be accepted)
\\Z4No\\Zn: (default, messages from misconfigured mail service providers will be treated as spam and rejected)
",
			['yes', 'no'],
			$dnsblCheckOnly ne 'yes' ? 'no' : 'yes'
		);
	}

	$self->{'config'}->{'DNSBL_CHECKS_ONLY'} = $dnsblCheckOnly if $rs != 30;

	$rs;
}

=item install()

 Process install tasks

 Return int 0 on success, other on failure

=cut

sub install
{
	my $self = $_[0];

	my $rs = $self->_bkpConfFile($self->{'config'}->{'POLICYD_CONF_FILE'});
	return $rs if $rs;

	$rs = $self->_buildConf();
	return $rs if $rs;

	$self->_saveConf();
}

=back

=head1 PRIVATE METHODS

=over 4

=item _init()

 Initialize instance

 Return Package::Policyd::Installer

=cut

sub _init
{
	my $self = $_[0];

	$self->{'policyd'} = Package::Policyd->getInstance();

	$self->{'cfgDir'} = $self->{'policyd'}->{'cfgDir'};
	$self->{'bkpDir'} = "$self->{'cfgDir'}/backup";
	$self->{'wrkDir'} = "$self->{'cfgDir'}/working";

	$self->{'config'} = $self->{'policyd'}->{'config'};

	# Merge old config file with new config file
	my $oldConf = "$self->{'cfgDir'}/policyd.old.data";
	if(-f $oldConf) {
		tie my %oldConfig, 'iMSCP::Config', 'fileName' => $oldConf;

		for(keys %oldConfig) {
			if(exists $self->{'config'}->{$_}) {
				$self->{'config'}->{$_} = $oldConfig{$_};
			}
		}
	}

	$self;
}

=item _bkpConfFile($cfgFile)

 Backup configuration file

 Param string $cfgFile Path of file to backup
 Return int 0 on success, other on failure

=cut

sub _bkpConfFile
{
	my ($self, $cfgFile) = @_;

	if(-f $cfgFile) {
		my $filename = fileparse($cfgFile);

		my $file = iMSCP::File->new('filename' => $cfgFile);
		my $rs = $file->copyFile("$self->{'bkpDir'}/$filename." . time);
		return $rs if $rs;
	}

	0;
}

=item _buildConf()

 Build configuration file

 Return int 0 on success, other on failure

=cut

sub _buildConf
{
	my $self = $_[0];

	my $rs = 0;
	my $uName = $self->{'config'}->{'POLICYD_USER'};
	my $gName = $self->{'config'}->{'POLICYD_GROUP'};
	my $policydConffile = $self->{'config'}->{'POLICYD_CONF_FILE'};
	my ($name, $path, $suffix) = fileparse($policydConffile);

	unless (-f $policydConffile) {
		my ($stdout, $stderr);
		$rs = execute("$self->{'config'}->{'POLICYD_BIN_FILE'} defaults > $policydConffile", \$stdout, \$stderr);
		debug($stdout) if $stdout;
		warning($stderr) if ! $rs && $stderr;
		error($stderr) if $rs && $stderr;
		error("Unable to create $policydConffile configuration file") if $rs && ! $stderr;
		return $rs if $rs;
	}

	my $file = iMSCP::File->new('filename' => $policydConffile);
	my $cfgTpl = $file->get();
	unless(defined $cfgTpl) {
		error("Unable to read $policydConffile file");
		return 1;
	}

	my $dnsblChecksOnly = ($self->{'config'}->{'DNSBL_CHECKS_ONLY'} eq 'yes') ? 1 : 0;
	$cfgTpl =~ s/^\s{0,}\$dnsbl_checks_only\s{0,}=.*$/\n   \$dnsbl_checks_only = $dnsblChecksOnly;          # 1: ON, 0: OFF (default)/mi;

	$file = iMSCP::File->new('filename' => "$self->{'wrkDir'}/$name$suffix");
	$rs = $file->set($cfgTpl);
	return $rs if $rs;

	$rs = $file->save();
	return $rs if $rs;

	$rs = $file->mode(0640);
	return $rs if $rs;

	$rs = $file->owner($uName, $gName);
	return $rs if $rs;

	$file->copyFile($policydConffile);
}

=item _saveConf()

 Save configuration

 Return int 0 on success, other on failure

=cut

sub _saveConf
{
	my $self = $_[0];

	iMSCP::File->new(
		'filename' => "$self->{'cfgDir'}/policyd.data"
	)->copyFile(
		"$self->{'cfgDir'}/policyd.old.data"
	);
}

=back

=head1 AUTHORS

 Daniel Andreca <sci2tech@gmail.com>
 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
