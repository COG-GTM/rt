use warnings;
use strict;

package ExternalStorage::App;

use FindBin;
use Mojo::Base 'Mojolicious', -signatures;
use Digest::SHA qw(sha256_hex);
use JSON::PP;
use YAML::Tiny;

use ExternalStorage::Backend;

my $backend;
my $app_config;

sub startup ($self) {
    $app_config = $self->_load_config;

    # Initialize backend at startup
    eval { $self->_get_backend };
    if ($@) {
        $self->log->warn("Backend not initialized at startup: $@");
        $self->log->warn("The /health endpoint will report unhealthy until configuration is fixed.");
    }

    my $r = $self->routes;

    # GET /health
    $r->get('/health' => sub ($c) {
        eval { $self->_get_backend };
        if ($@) {
            return $c->render(json => {
                status  => 'unhealthy',
                error   => "$@",
                backend => $app_config->{storage_type} // 'unconfigured',
            }, status => 503);
        }
        $c->render(json => {
            status  => 'healthy',
            backend => $app_config->{storage_type},
        });
    });

    # GET /blob/:sha256
    $r->get('/blob/:sha256' => sub ($c) {
        my $sha = $c->param('sha256');
        my $be = eval { $self->_get_backend };
        return $c->render(json => { error => "$@" }, status => 503) if $@;

        my ($content, $error) = $be->Get($sha);
        if (defined $content) {
            $c->render(data => $content, format => 'bin');
        }
        else {
            my $status = _error_status($error);
            $c->render(json => { error => $error // "Not found" }, status => $status);
        }
    });

    # PUT /blob/:sha256
    $r->put('/blob/:sha256' => sub ($c) {
        my $sha  = $c->param('sha256');
        my $body = $c->req->body;

        unless (length $body) {
            return $c->render(json => { error => "Empty request body" }, status => 400);
        }

        my $be = eval { $self->_get_backend };
        return $c->render(json => { error => "$@" }, status => 503) if $@;

        my $computed_sha = sha256_hex($body);
        if ($sha ne $computed_sha) {
            return $c->render(json => {
                error        => "SHA-256 mismatch: URL has $sha but content hashes to $computed_sha",
                expected_sha => $sha,
                actual_sha   => $computed_sha,
            }, status => 400);
        }

        my $content_type = $c->req->headers->content_type // '';
        my ($result, $error) = $be->Store($sha, $body, $content_type);
        if (defined $result) {
            $c->render(json => { sha256 => $result }, status => 200);
        }
        else {
            $c->render(json => { error => $error }, status => 500);
        }
    });

    # DELETE /blob/:sha256
    $r->delete('/blob/:sha256' => sub ($c) {
        my $sha = $c->param('sha256');
        my $be = eval { $self->_get_backend };
        return $c->render(json => { error => "$@" }, status => 503) if $@;

        my ($result, $error) = $be->Delete($sha);
        if (defined $result) {
            $c->render(json => { sha256 => $result, deleted => JSON::PP::true }, status => 200);
        }
        else {
            $c->render(json => { error => $error }, status => 500);
        }
    });

    # GET /download-url/:sha256
    $r->get('/download-url/:sha256' => sub ($c) {
        my $sha = $c->param('sha256');
        my $be = eval { $self->_get_backend };
        return $c->render(json => { error => "$@" }, status => 503) if $@;

        my $url = $be->DownloadURLFor($sha);
        $c->render(json => { sha256 => $sha, url => $url });
    });

    # POST /blob
    $r->post('/blob' => sub ($c) {
        my $body = $c->req->body;

        unless (length $body) {
            return $c->render(json => { error => "Empty request body" }, status => 400);
        }

        my $be = eval { $self->_get_backend };
        return $c->render(json => { error => "$@" }, status => 503) if $@;

        my $sha = sha256_hex($body);
        my $content_type = $c->req->headers->content_type // '';

        my ($result, $error) = $be->Store($sha, $body, $content_type);
        if (defined $result) {
            $c->render(json => { sha256 => $result }, status => 201);
        }
        else {
            $c->render(json => { error => $error }, status => 500);
        }
    });
}

sub _load_config ($self) {
    my %cfg;

    my $config_file = $ENV{ESS_CONFIG_FILE}
        || "$FindBin::Bin/../etc/config.yml";

    if (-f $config_file) {
        my $yaml = YAML::Tiny->read($config_file);
        if ($yaml && $yaml->[0]) {
            %cfg = %{ $yaml->[0] };
        }
    }

    $cfg{storage_type} = $ENV{STORAGE_TYPE} if $ENV{STORAGE_TYPE};
    $cfg{listen}       = $ENV{ESS_LISTEN}   if $ENV{ESS_LISTEN};

    # Disk backend
    $cfg{storage_path} = $ENV{STORAGE_PATH} if $ENV{STORAGE_PATH};

    # S3 backend
    $cfg{s3_access_key_id}     = $ENV{S3_ACCESS_KEY_ID}     if $ENV{S3_ACCESS_KEY_ID};
    $cfg{s3_secret_access_key} = $ENV{S3_SECRET_ACCESS_KEY} if $ENV{S3_SECRET_ACCESS_KEY};
    $cfg{s3_bucket}            = $ENV{S3_BUCKET}            if $ENV{S3_BUCKET};
    $cfg{s3_host}              = $ENV{S3_HOST}               if $ENV{S3_HOST};
    $cfg{s3_region}            = $ENV{S3_REGION}             if $ENV{S3_REGION};

    # Dropbox backend
    $cfg{dropbox_app_key}       = $ENV{DROPBOX_APP_KEY}       if $ENV{DROPBOX_APP_KEY};
    $cfg{dropbox_app_secret}    = $ENV{DROPBOX_APP_SECRET}    if $ENV{DROPBOX_APP_SECRET};
    $cfg{dropbox_refresh_token} = $ENV{DROPBOX_REFRESH_TOKEN} if $ENV{DROPBOX_REFRESH_TOKEN};

    return \%cfg;
}

sub _get_backend ($self) {
    return $backend if $backend;

    my $type = $app_config->{storage_type};
    unless ($type) {
        die "No storage_type configured. Set STORAGE_TYPE env var or storage_type in config.yml\n";
    }

    my %args;
    if ($type eq 'Disk') {
        $args{Path} = $app_config->{storage_path}
            or die "Disk backend requires storage_path / STORAGE_PATH\n";
    }
    elsif ($type eq 'AmazonS3') {
        $args{AccessKeyId}     = $app_config->{s3_access_key_id}     or die "AmazonS3 backend requires s3_access_key_id / S3_ACCESS_KEY_ID\n";
        $args{SecretAccessKey} = $app_config->{s3_secret_access_key} or die "AmazonS3 backend requires s3_secret_access_key / S3_SECRET_ACCESS_KEY\n";
        $args{Bucket}          = $app_config->{s3_bucket}            or die "AmazonS3 backend requires s3_bucket / S3_BUCKET\n";
        $args{Host}            = $app_config->{s3_host}   if $app_config->{s3_host};
        $args{Region}          = $app_config->{s3_region} if $app_config->{s3_region};
    }
    elsif ($type eq 'Dropbox') {
        $args{AppKey}       = $app_config->{dropbox_app_key}       or die "Dropbox backend requires dropbox_app_key / DROPBOX_APP_KEY\n";
        $args{AppSecret}    = $app_config->{dropbox_app_secret}    or die "Dropbox backend requires dropbox_app_secret / DROPBOX_APP_SECRET\n";
        $args{RefreshToken} = $app_config->{dropbox_refresh_token} or die "Dropbox backend requires dropbox_refresh_token / DROPBOX_REFRESH_TOKEN\n";
    }
    else {
        die "Unknown storage type: $type\n";
    }

    $backend = ExternalStorage::Backend->new(Type => $type, %args);
    unless ($backend) {
        die "Failed to initialize $type storage backend\n";
    }

    return $backend;
}

# Map backend error strings to HTTP status codes
sub _error_status {
    my $error = shift // '';
    return 404 if $error =~ /does not exist|[Nn]ot found/;
    return 400 if $error =~ /[Ii]nvalid/;
    return 500;
}

# Allow resetting backend (used by tests)
sub reset_backend {
    $backend = undef;
}

1;
