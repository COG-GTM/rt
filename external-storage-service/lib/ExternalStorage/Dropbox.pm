use warnings;
use strict;

package ExternalStorage::Dropbox;

use Role::Basic qw/with/;
with 'ExternalStorage::Backend';

sub DropboxClient {
    my $self = shift;
    if (@_) {
        $self->{DropboxClient} = shift;
    }
    return $self->{DropboxClient};
}

sub AppKey {
    my $self = shift;
    return $self->{AppKey};
}

sub AppSecret {
    my $self = shift;
    return $self->{AppSecret};
}

sub RefreshToken {
    my $self = shift;
    return $self->{RefreshToken};
}

sub Init {
    my $self = shift;

    eval { require WebService::Dropbox };
    if ($@) {
        warn "Required module WebService::Dropbox is not installed: $@\n";
        return;
    }

    for my $item (qw/AppKey AppSecret RefreshToken/) {
        next if $self->$item;
        warn "Required option '$item' not provided for Dropbox external storage.\n";
        return;
    }

    my $dropbox = WebService::Dropbox->new({
        key    => $self->AppKey,
        secret => $self->AppSecret,
    });

    $dropbox->refresh_access_token($self->RefreshToken);
    $self->DropboxClient($dropbox);

    return $self;
}

# Dropbox requires the "/" prefix
sub _FilePath {
    my $self = shift;
    my $sha  = shift;
    return "/$sha";
}

sub _PathExists {
    my $self = shift;
    my $path = shift;

    # Get rid of expected warnings when path doesn't exist
    local $SIG{__WARN__} = sub {};
    return $self->DropboxClient->get_metadata($path);
}

sub Get {
    my $self = shift;
    my ($sha) = @_;
    my $path = $self->_FilePath($sha);

    my $content;
    open my $fh, '>', \$content;
    $self->DropboxClient->download($path, $fh);
    close $fh;
    if (defined $content && length $content) {
        return ($content);
    }
    else {
        return (undef, "Read $sha from dropbox failed: " . $self->DropboxClient->error);
    }
}

sub Store {
    my $self = shift;
    my ($sha, $content, $content_type) = @_;

    my $path = $self->_FilePath($sha);

    # No-op if the path exists already.
    return ($sha) if $self->_PathExists($path);

    if ($self->DropboxClient->upload($path, $content)) {
        return ($sha);
    }
    else {
        return (undef, "Write $sha to dropbox failed: " . $self->DropboxClient->error);
    }
}

sub DownloadURLFor {
    return;
}

sub Delete {
    my $self = shift;
    my $sha  = shift;
    my $path = $self->_FilePath($sha);

    if ($self->_PathExists($path) && !$self->DropboxClient->delete($path)) {
        return (undef, "Delete $sha from dropbox failed: " . $self->DropboxClient->error);
    }
    return ($sha);
}

1;
