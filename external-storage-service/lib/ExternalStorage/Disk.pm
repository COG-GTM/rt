use warnings;
use strict;

package ExternalStorage::Disk;

use File::Path qw//;
use File::Basename 'dirname';
use Role::Basic qw/with/;
with 'ExternalStorage::Backend';

sub Path {
    my $self = shift;
    return $self->{Path};
}

sub Init {
    my $self = shift;

    if (not $self->Path) {
        warn "Required option 'Path' not provided for Disk external storage.\n";
        return;
    } elsif (not -e $self->Path) {
        warn "Path provided for Disk external storage (" . $self->Path . ") does not exist\n";
        return;
    }

    return $self;
}

sub IsWriteable {
    my $self = shift;

    if (not -w $self->Path) {
        return (undef, "Path provided for local storage (" . $self->Path . ") is not writable");
    }

    return (1);
}

sub _FilePath {
    my $self = shift;
    my $sha  = shift;

    # fan out to avoid one gigantic directory which slows down all file access
    unless ($sha =~ m{^(...)(...)(.*)}) {
        return undef;
    }
    return $self->Path . "/$1/$2/$3";
}

sub Get {
    my $self = shift;
    my ($sha) = @_;

    my $path = $self->_FilePath($sha);
    return (undef, "Invalid SHA value") unless defined $path;

    return (undef, "File does not exist") unless -e $path;

    open(my $fh, "<", $path) or return (undef, "Cannot read file on disk: $!");
    my $content = do { local $/; <$fh> };
    $content = "" unless defined $content;
    close $fh;

    return ($content);
}

sub Store {
    my $self = shift;
    my ($sha, $content, $content_type) = @_;
    my $path = $self->_FilePath($sha);
    return (undef, "Invalid SHA value") unless defined $path;

    return ($sha) if -f $path;

    File::Path::make_path(dirname($path), { error => \my $err });
    return (undef, "Making directory failed") if @{$err};

    open(my $fh, ">:raw", $path) or return (undef, "Cannot write file on disk: $!");
    print $fh $content or return (undef, "Cannot write file to disk: $!");
    close $fh or return (undef, "Cannot write file to disk: $!");

    return ($sha);
}

sub DownloadURLFor {
    return;
}

sub Delete {
    my $self = shift;
    my $sha  = shift;
    my $path = $self->_FilePath($sha);
    return (undef, "Invalid SHA value") unless defined $path;

    if (-f $path) {
        unlink $path or return (undef, "Cannot delete file: $!");
    }
    return ($sha);
}

1;
