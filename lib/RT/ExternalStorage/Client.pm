# BEGIN BPS TAGGED BLOCK {{{
#
# COPYRIGHT:
#
# This software is Copyright (c) 1996-2025 Best Practical Solutions, LLC
#                                          <sales@bestpractical.com>
#
# (Except where explicitly superseded by other copyright notices)
#
#
# LICENSE:
#
# This work is made available to you under the terms of Version 2 of
# the GNU General Public License. A copy of that license should have
# been provided with this software, but in any event can be snarfed
# from www.gnu.org.
#
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301 or visit their web page on the internet at
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.html.
#
#
# CONTRIBUTION SUBMISSION POLICY:
#
# (The following paragraph is not intended to limit the rights granted
# to you to modify and distribute this software under the terms of
# the GNU General Public License and is only of importance to you if
# you choose to contribute your changes and enhancements to the
# community by submitting them to Best Practical Solutions, LLC.)
#
# By intentionally submitting any modifications, corrections or
# derivatives to this work, or any other work intended for use with
# Request Tracker, to Best Practical Solutions, LLC, you confirm that
# you are the copyright holder for those contributions and you grant
# Best Practical Solutions,  LLC a nonexclusive, worldwide, irrevocable,
# royalty-free, perpetual, license to use, copy, create derivative
# works based on those contributions, and sublicense and distribute
# those contributions and any derivatives thereof.
#
# END BPS TAGGED BLOCK }}}

use warnings;
use strict;

package RT::ExternalStorage::Client;

use LWP::UserAgent;
use HTTP::Request;
use Role::Basic qw/with/;
with 'RT::ExternalStorage::Backend';

sub new {
    my $class = shift;
    my %args = @_;
    my $self = bless \%args, $class;
    return $self->Init ? $self : undef;
}

sub ServiceURL {
    my $self = shift;
    my $url = $self->{ServiceURL};
    # Strip trailing slash for consistent URL construction
    $url =~ s{/+$}{} if $url;
    return $url;
}

sub _ua {
    my $self = shift;
    unless ($self->{_ua}) {
        $self->{_ua} = LWP::UserAgent->new(
            agent   => 'RT-ExternalStorage-Client/1.0',
            timeout => 30,
        );
    }
    return $self->{_ua};
}

sub Init {
    my $self = shift;

    if (not $self->ServiceURL) {
        RT->Logger->error("Required option 'ServiceURL' not provided for ExternalStorage Client.");
        return;
    }

    my $url = $self->ServiceURL . '/health';
    my $response = $self->_ua->get($url);

    unless ($response->is_success) {
        RT->Logger->error(
            "External storage service health check failed at $url: "
            . $response->status_line
        );
        return;
    }

    return $self;
}

sub Get {
    my $self = shift;
    my ($sha) = @_;

    my $url = $self->ServiceURL . '/blob/' . $sha;
    my $response = $self->_ua->get($url);

    unless ($response->is_success) {
        return (undef, "Failed to retrieve $sha from external storage service: " . $response->status_line);
    }

    return ($response->decoded_content(charset => 'none'));
}

sub Store {
    my $self = shift;
    my ($sha, $content, $attachment) = @_;

    my $url = $self->ServiceURL . '/blob/' . $sha;

    my $content_type = 'application/octet-stream';
    if ($attachment && $attachment->can('ContentType')) {
        $content_type = $attachment->ContentType;
    }

    my $request = HTTP::Request->new(PUT => $url);
    $request->content_type($content_type);
    $request->content($content);

    my $response = $self->_ua->request($request);

    unless ($response->is_success) {
        return (undef, "Failed to store $sha in external storage service: " . $response->status_line);
    }

    return ($sha);
}

sub Delete {
    my $self = shift;
    my ($sha) = @_;

    my $url = $self->ServiceURL . '/blob/' . $sha;

    my $request = HTTP::Request->new(DELETE => $url);
    my $response = $self->_ua->request($request);

    unless ($response->is_success) {
        return (undef, "Failed to delete $sha from external storage service: " . $response->status_line);
    }

    return ($sha);
}

sub DownloadURLFor {
    my $self = shift;
    my $object = shift;

    my $column = $object->isa('RT::Attachment') ? 'Content' : 'LargeContent';
    my $digest = $object->__Value($column);

    return undef unless $digest;

    my $url = $self->ServiceURL . '/download-url/' . $digest;
    my $response = $self->_ua->get($url);

    unless ($response->is_success) {
        RT->Logger->warning(
            "Failed to get download URL for $digest from external storage service: "
            . $response->status_line
        );
        return undef;
    }

    my $download_url = $response->decoded_content;
    # Strip any surrounding whitespace/newlines
    $download_url =~ s/^\s+|\s+$//g;

    return $download_url || undef;
}

=head1 NAME

RT::ExternalStorage::Client - HTTP client for the standalone External Storage service

=head1 SYNOPSIS

    Set($ExternalStorageURL, 'http://external-storage.example.com:8080');

=head1 DESCRIPTION

This storage engine talks to a standalone External Storage HTTP service
instead of accessing storage backends directly in-process. It implements the
same interface as the other backends (L<RT::ExternalStorage::Disk>,
L<RT::ExternalStorage::AmazonS3>, etc.) so it is a drop-in replacement.

Configure C<$ExternalStorageURL> in your F<RT_SiteConfig.pm> to use this
client. When set, RT will use this HTTP client instead of the legacy
in-process backends configured via C<%ExternalStorage>.

The service is expected to expose the following endpoints:

=over

=item GET /health

Returns 200 if the service is operational.

=item GET /blob/$sha256

Returns the stored content for the given SHA-256 digest.

=item PUT /blob/$sha256

Stores content under the given SHA-256 digest. The request body is the
content bytes.

=item DELETE /blob/$sha256

Deletes the content for the given SHA-256 digest.

=item GET /download-url/$sha256

Returns a direct-download URL for the given digest.

=back

=head1 CONFIGURATION

=over

=item C<$ExternalStorageURL>

The base URL of the External Storage service (e.g.
C<http://external-storage.example.com:8080>). When this is set, RT will
use the HTTP client instead of in-process backends.

=back

=cut

require RT::Base;
RT::Base->_ImportOverlays();

1;
