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

use Role::Basic qw/with/;
with 'RT::ExternalStorage::Backend';

sub ServiceURL {
    my $self = shift;
    return $self->{ServiceURL};
}

sub Init {
    my $self = shift;

    if (not $self->{ServiceURL}) {
        RT->Logger->error("Required option 'ServiceURL' not provided for Client external storage.");
        return;
    }

    if (not LWP::UserAgent->require) {
        RT->Logger->error("Required module LWP::UserAgent is not installed");
        return;
    }
    LWP::UserAgent->import;

    if (not HTTP::Request->require) {
        RT->Logger->error("Required module HTTP::Request is not installed");
        return;
    }
    HTTP::Request->import;

    # Strip trailing slash for consistency
    $self->{ServiceURL} =~ s{/+$}{};

    $self->{_ua} = LWP::UserAgent->new(
        agent   => "RT-ExternalStorage-Client/1.0",
        timeout => 300,
    );

    return $self;
}

sub _ua {
    my $self = shift;
    return $self->{_ua};
}

sub Get {
    my $self = shift;
    my ($sha) = @_;

    my $url = $self->ServiceURL . "/store/$sha";
    my $response = $self->_ua->get($url);

    if ($response->is_success) {
        return ($response->decoded_content(charset => 'none'));
    }

    return (undef, "GET $url failed: " . $response->status_line);
}

sub Store {
    my $self = shift;
    my ($sha, $content, $attachment) = @_;

    my $url = $self->ServiceURL . "/store/$sha";

    my $content_type = 'application/octet-stream';
    if ($attachment && $attachment->can('ContentType') && $attachment->ContentType) {
        $content_type = $attachment->ContentType;
    }

    my $request = HTTP::Request->new(PUT => $url);
    $request->header('Content-Type' => $content_type);
    $request->content($content);

    my $response = $self->_ua->request($request);

    if ($response->is_success) {
        return ($sha);
    }

    return (undef, "PUT $url failed: " . $response->status_line);
}

sub Delete {
    my $self = shift;
    my ($sha) = @_;

    my $url = $self->ServiceURL . "/store/$sha";
    my $response = $self->_ua->delete($url);

    if ($response->is_success) {
        return ($sha);
    }

    return (undef, "DELETE $url failed: " . $response->status_line);
}

sub DownloadURLFor {
    my $self = shift;
    my $object = shift;

    my $column = $object->isa('RT::Attachment') ? 'Content' : 'LargeContent';
    my $digest = $object->__Value($column);

    return $self->ServiceURL . "/store/$digest";
}

=head1 NAME

RT::ExternalStorage::Client - HTTP client for external storage service

=head1 SYNOPSIS

    Set($ExternalStorageURL, 'http://localhost:8080');

=head1 DESCRIPTION

This module communicates with a standalone External Storage HTTP service,
delegating all storage operations over HTTP rather than accessing the
storage backend directly in-process.

When C<$ExternalStorageURL> is configured in F<RT_SiteConfig.pm>, RT will
use this client instead of a direct backend (Disk, S3, Dropbox, etc.).

The client implements the same C<Store>/C<Get>/C<Delete> interface as the
direct backends, so it is a drop-in replacement from the perspective of
callers like C<sbin/rt-externalize-attachments>.

=head1 HTTP API

The service is expected to expose the following endpoints:

=over

=item GET /store/:sha

Retrieve the content for the given SHA-256 digest.

=item PUT /store/:sha

Store content under the given SHA-256 digest.  The request body is the
raw content.  A C<Content-Type> header is sent when available from the
attachment metadata.

=item DELETE /store/:sha

Remove the content for the given SHA-256 digest.

=back

=cut

require RT::Base;
RT::Base->_ImportOverlays();

1;
