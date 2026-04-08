use warnings;
use strict;

package ExternalStorage::AmazonS3;

use Role::Basic qw/with/;
with 'ExternalStorage::Backend';

sub S3 {
    my $self = shift;
    if (@_) {
        $self->{S3} = shift;
    }
    return $self->{S3};
}

sub Bucket {
    my $self = shift;
    return $self->{Bucket};
}

sub AccessKeyId {
    my $self = shift;
    return $self->{AccessKeyId};
}

sub SecretAccessKey {
    my $self = shift;
    return $self->{SecretAccessKey};
}

sub BucketObj {
    my $self = shift;
    return $self->S3->bucket($self->Bucket);
}

sub Init {
    my $self = shift;

    eval { require Amazon::S3 };
    if ($@) {
        warn "Required module Amazon::S3 is not installed: $@\n";
        return;
    }

    for my $key (qw/AccessKeyId SecretAccessKey Bucket/) {
        if (not $self->$key) {
            warn "Required option '$key' not provided for AmazonS3 external storage.\n";
            return;
        }
    }

    my %args = (
        aws_access_key_id     => $self->AccessKeyId,
        aws_secret_access_key => $self->SecretAccessKey,
        retry                 => 1,
    );
    $args{host}   = $self->{Host}   if $self->{Host};
    $args{region} = $self->{Region} if $self->{Region};

    my $S3 = Amazon::S3->new(\%args);
    $self->S3($S3);

    # Note: bucket existence is validated lazily on first Store/Get/Delete
    # operation. $S3->bucket() only creates a local handle without an API call.

    return $self;
}

sub Get {
    my $self = shift;
    my ($sha) = @_;

    my $ok = $self->BucketObj->get_key($sha);
    return (undef, "Could not retrieve from AmazonS3: " . $self->S3->errstr)
        unless $ok;
    return ($ok->{value});
}

sub Store {
    my $self = shift;
    my ($sha, $content, $content_type) = @_;

    # No-op if the path exists already
    return ($sha) if $self->BucketObj->head_key($sha);

    my %opts;
    $opts{content_type} = $content_type if $content_type;

    $self->BucketObj->add_key(
        $sha => $content,
        \%opts,
    ) or return (undef, "Failed to write to AmazonS3: " . $self->S3->errstr);

    return ($sha);
}

sub DownloadURLFor {
    my $self   = shift;
    my $digest = shift;

    if ($self->{Host}) {
        return "https://" . $self->{Host} . "/" . $self->Bucket . "/" . $digest;
    }
    elsif ($self->{Region}) {
        return "https://" . $self->Bucket . ".s3." . $self->{Region} . ".amazonaws.com/" . $digest;
    }
    return "https://" . $self->Bucket . ".s3.amazonaws.com/" . $digest;
}

sub Delete {
    my $self = shift;
    my $sha  = shift;

    if ($self->BucketObj->head_key($sha)) {
        $self->BucketObj->delete_key($sha)
            or return (undef, "Failed to delete $sha from AmazonS3: " . $self->S3->errstr);
    }

    return ($sha);
}

1;
