#!/usr/bin/env perl
use strict;
use warnings;

use Test::More;
use Test::Mojo;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";

# ---------------------------------------------------------------------------
# Test: Healthy backend
# ---------------------------------------------------------------------------
my $tmpdir = tempdir(CLEANUP => 1);
$ENV{STORAGE_TYPE} = 'Disk';
$ENV{STORAGE_PATH} = $tmpdir;

require ExternalStorage::App;
ExternalStorage::App->reset_backend;

my $t = Test::Mojo->new('ExternalStorage::App');

$t->get_ok('/health')
  ->status_is(200)
  ->json_is('/status' => 'healthy')
  ->json_is('/backend' => 'Disk');

# Verify response is valid JSON
my $json = $t->tx->res->json;
ok(exists $json->{status}, 'Health response has status field');
ok(exists $json->{backend}, 'Health response has backend field');

# ---------------------------------------------------------------------------
# Test: Multiple health checks in succession
# ---------------------------------------------------------------------------
for my $i (1..3) {
    $t->get_ok('/health')
      ->status_is(200)
      ->json_is('/status' => 'healthy');
}

done_testing();
