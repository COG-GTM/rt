#!/usr/bin/env perl
use strict;
use warnings;

use Test::More;
use Test::Mojo;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Digest::SHA qw(sha256_hex);

# Create a temporary directory for disk storage
my $tmpdir = tempdir(CLEANUP => 1);

# Set environment for the server
$ENV{STORAGE_TYPE} = 'Disk';
$ENV{STORAGE_PATH} = $tmpdir;

# Reset backend state for fresh test
require ExternalStorage::App;
ExternalStorage::App->reset_backend;

# Load the app via the class
my $t = Test::Mojo->new('ExternalStorage::App');

# ---------------------------------------------------------------------------
# Test: GET /health
# ---------------------------------------------------------------------------
$t->get_ok('/health')
  ->status_is(200)
  ->json_is('/status' => 'healthy')
  ->json_is('/backend' => 'Disk');

# ---------------------------------------------------------------------------
# Test: POST /blob - Store with auto-computed SHA-256
# ---------------------------------------------------------------------------
my $content = "Test content for HTTP API";
my $expected_sha = sha256_hex($content);

$t->post_ok('/blob' => $content)
  ->status_is(201)
  ->json_is('/sha256' => $expected_sha);

# ---------------------------------------------------------------------------
# Test: GET /blob/:sha256 - Retrieve stored blob
# ---------------------------------------------------------------------------
$t->get_ok("/blob/$expected_sha")
  ->status_is(200)
  ->content_is($content);

# ---------------------------------------------------------------------------
# Test: PUT /blob/:sha256 - Store with explicit SHA
# ---------------------------------------------------------------------------
my $content2 = "Another piece of content";
my $sha2 = sha256_hex($content2);

$t->put_ok("/blob/$sha2" => $content2)
  ->status_is(200)
  ->json_is('/sha256' => $sha2);

# Verify it can be retrieved
$t->get_ok("/blob/$sha2")
  ->status_is(200)
  ->content_is($content2);

# ---------------------------------------------------------------------------
# Test: PUT /blob/:sha256 - SHA mismatch returns 400
# ---------------------------------------------------------------------------
$t->put_ok("/blob/invalidsha256value" => "some content")
  ->status_is(400)
  ->json_has('/error');

# ---------------------------------------------------------------------------
# Test: PUT /blob/:sha256 - Empty body returns 400
# ---------------------------------------------------------------------------
$t->put_ok("/blob/$sha2" => '')
  ->status_is(400)
  ->json_is('/error' => 'Empty request body');

# ---------------------------------------------------------------------------
# Test: GET /download-url/:sha256 - Disk backend returns null URL
# ---------------------------------------------------------------------------
$t->get_ok("/download-url/$expected_sha")
  ->status_is(200)
  ->json_is('/sha256' => $expected_sha)
  ->json_is('/url' => undef);

# ---------------------------------------------------------------------------
# Test: DELETE /blob/:sha256 - Delete a blob
# ---------------------------------------------------------------------------
$t->delete_ok("/blob/$expected_sha")
  ->status_is(200)
  ->json_is('/sha256' => $expected_sha)
  ->json_is('/deleted' => Mojo::JSON::true);

# Verify it's gone
$t->get_ok("/blob/$expected_sha")
  ->status_is(404);

# ---------------------------------------------------------------------------
# Test: GET /blob/:sha256 - Non-existent blob returns 404
# ---------------------------------------------------------------------------
$t->get_ok('/blob/0000000000000000000000000000000000000000000000000000000000000000')
  ->status_is(404)
  ->json_has('/error');

# ---------------------------------------------------------------------------
# Test: POST /blob - Empty body returns 400
# ---------------------------------------------------------------------------
$t->post_ok('/blob' => '')
  ->status_is(400)
  ->json_is('/error' => 'Empty request body');

# ---------------------------------------------------------------------------
# Test: PUT with Content-Type header (for S3 passthrough)
# ---------------------------------------------------------------------------
my $typed_content = '{"key": "value"}';
my $typed_sha = sha256_hex($typed_content);

$t->put_ok("/blob/$typed_sha" => { 'Content-Type' => 'application/json' } => $typed_content)
  ->status_is(200)
  ->json_is('/sha256' => $typed_sha);

# ---------------------------------------------------------------------------
# Test: Binary content round-trip
# ---------------------------------------------------------------------------
my $binary = join('', map { chr($_) } 0..255);
my $binary_sha = sha256_hex($binary);

$t->put_ok("/blob/$binary_sha" => $binary)
  ->status_is(200)
  ->json_is('/sha256' => $binary_sha);

$t->get_ok("/blob/$binary_sha")
  ->status_is(200)
  ->content_is($binary);

done_testing();
