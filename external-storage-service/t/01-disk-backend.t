#!/usr/bin/env perl
use strict;
use warnings;

use Test::More;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";

use Digest::SHA qw(sha256_hex);
use ExternalStorage::Backend;

# Create a temporary directory for disk storage
my $tmpdir = tempdir(CLEANUP => 1);

# Test backend creation
my $backend = ExternalStorage::Backend->new(
    Type => 'Disk',
    Path => $tmpdir,
);
ok($backend, 'Disk backend created successfully');
isa_ok($backend, 'ExternalStorage::Disk');

# Test Store
my $content = "Hello, External Storage!";
my $sha = sha256_hex($content);

my ($result, $error) = $backend->Store($sha, $content);
is($result, $sha, 'Store returns the SHA-256 digest');
ok(!$error, 'Store has no error');

# Test Store idempotency (no-op if exists)
my ($result2, $error2) = $backend->Store($sha, $content);
is($result2, $sha, 'Store is idempotent - returns same SHA');
ok(!$error2, 'Store idempotent has no error');

# Test Get
my ($retrieved, $get_error) = $backend->Get($sha);
is($retrieved, $content, 'Get returns the stored content');
ok(!$get_error, 'Get has no error');

# Test Get for non-existent file
my ($missing, $missing_error) = $backend->Get('nonexistent_sha_value_that_does_not_exist');
ok(!defined $missing, 'Get returns undef for non-existent file');
ok($missing_error, 'Get returns an error for non-existent file');

# Test DownloadURLFor (Disk returns undef)
my $url = $backend->DownloadURLFor($sha);
ok(!defined $url, 'DownloadURLFor returns undef for Disk backend');

# Test Delete
my ($del_result, $del_error) = $backend->Delete($sha);
is($del_result, $sha, 'Delete returns the SHA-256 digest');
ok(!$del_error, 'Delete has no error');

# Verify file is gone after delete
my ($after_del, $after_del_error) = $backend->Get($sha);
ok(!defined $after_del, 'Get returns undef after Delete');

# Test Delete for non-existent file (should be a no-op)
my ($del_noop, $del_noop_error) = $backend->Delete('nonexistent_sha_value');
is($del_noop, 'nonexistent_sha_value', 'Delete of non-existent file is a no-op');
ok(!$del_noop_error, 'Delete of non-existent file has no error');

# Test fan-out directory structure
my $content2 = "Another test file for fan-out verification";
my $sha2 = sha256_hex($content2);
$backend->Store($sha2, $content2);

# Verify the fan-out structure: $path/$first3/$next3/$rest
my $first3 = substr($sha2, 0, 3);
my $next3  = substr($sha2, 3, 3);
my $rest   = substr($sha2, 6);
my $expected_path = "$tmpdir/$first3/$next3/$rest";
ok(-f $expected_path, 'File stored in fan-out directory structure');

# Test binary content
my $binary = join('', map { chr($_) } 0..255);
my $binary_sha = sha256_hex($binary);
$backend->Store($binary_sha, $binary);
my ($bin_retrieved) = $backend->Get($binary_sha);
is($bin_retrieved, $binary, 'Binary content stored and retrieved correctly');

# Test invalid backend creation
my $bad_backend = ExternalStorage::Backend->new(
    Type => 'Disk',
    Path => '/nonexistent/path/that/does/not/exist',
);
ok(!$bad_backend, 'Backend creation fails with invalid path');

my $no_type = ExternalStorage::Backend->new();
ok(!$no_type, 'Backend creation fails without Type');

done_testing();
