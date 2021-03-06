=head1 NAME

Package::FileManager::Pydio::Uninstaller - i-MSCP Pydio package uninstaller

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
# @author      Laurent Declercq <l.declercq@nuxwin.com>
# @link        http://i-mscp.net i-MSCP Home Site
# @license     http://www.gnu.org/licenses/gpl-2.0.html GPL v2

package Package::FileManager::Pydio::Uninstaller;

use strict;
use warnings;

use iMSCP::Debug;
use iMSCP::Dir;
use iMSCP::File;
use iMSCP::Execute;
use Package::FrontEnd;
use parent 'Common::SingletonClass';

=head1 DESCRIPTION

 i-MSCP Pydio package uninstaller.

=head1 PUBLIC METHODS

=over 4

=item uninstall()

 Process uninstall tasks

 Return int 0 on success, other on failure

=cut

sub uninstall
{
	my $self = $_[0];

	my $rs = $self->_unregisterConfig();
	return $rs if $rs;

	$self->_removeFiles();
}

=back

=head1 PRIVATE METHODS

=over 4

=item _init()

 Initialize instance

 Return Package::FileManager::Pydio::Uninstaller

=cut

sub _init
{
	my $self = $_[0];

	$self->{'frontend'} = Package::FrontEnd->getInstance();

	$self;
}

=item _unregisterConfig

 Remove include directive from frontEnd vhost files

 Return int 0 on success, other on failure

=cut

sub _unregisterConfig
{
	my $self = $_[0];

	for my $vhostFile('00_master.conf', '00_master_ssl.conf') {
		if(-f "$self->{'frontend'}->{'config'}->{'HTTPD_SITES_AVAILABLE_DIR'}/$vhostFile") {
			my $file = iMSCP::File->new(
				filename => "$self->{'frontend'}->{'config'}->{'HTTPD_SITES_AVAILABLE_DIR'}/$vhostFile"
			);

			my $fileContent = $file->get();
			unless(defined $fileContent) {
				error("Unable to read file $file->{'filename'}");
				return 1;
			}

			$fileContent =~ s/[\t ]*include imscp_pydio.conf;\n//;

			my $rs = $file->set($fileContent);
			return $rs if $rs;

			$rs = $file->save();
			return $rs if $rs;
		}
	}

	$self->{'frontend'}->{'reload'} = 1;

	0;
}

=item _removeFiles()

 Remove files

 Return int 0 on success, other on failure

=cut

sub _removeFiles
{
	my $self = $_[0];

	my $rs = iMSCP::Dir->new( dirname =>  "$main::imscpConfig{'GUI_PUBLIC_DIR'}/tools/ftp" )->remove();
	return $rs if $rs;

	if(-f "$self->{'frontend'}->{'config'}->{'HTTPD_CONF_DIR'}/imscp_pydio.conf") {
		$rs = iMSCP::File->new(
			filename => "$self->{'frontend'}->{'config'}->{'HTTPD_CONF_DIR'}/imscp_pydio.conf"
		)->delFile();
		return $rs if $rs;
	}

	0;
}

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
__END__
