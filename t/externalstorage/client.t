use strict;
use warnings;

use RT::Test tests => undef;
use Test::MockObject;

# Test that RT::ExternalStorage::Client can be loaded
use_ok('RT::ExternalStorage::Client');

# Test that Client implements the Backend role
ok( RT::ExternalStorage::Client->DOES('RT::ExternalStorage::Backend'),
    'Client implements the Backend role' );

# Test Client instantiation with required parameters
{
    my $client = RT::ExternalStorage::Client->new(
        Type       => 'RT::ExternalStorage::Client',
        ServiceURL => 'http://localhost:8080',
    );
    ok( $client, 'Client instantiated successfully' );
    isa_ok( $client, 'RT::ExternalStorage::Client' );
    is( $client->ServiceURL, 'http://localhost:8080',
        'ServiceURL is set correctly' );
}

# Test that trailing slash is stripped from ServiceURL
{
    my $client = RT::ExternalStorage::Client->new(
        Type       => 'RT::ExternalStorage::Client',
        ServiceURL => 'http://localhost:8080/',
    );
    ok( $client, 'Client instantiated with trailing slash' );
    is( $client->ServiceURL, 'http://localhost:8080',
        'Trailing slash is stripped from ServiceURL' );
}

# Test instantiation fails without ServiceURL
{
    my $client = RT::ExternalStorage::Client->new(
        Type => 'RT::ExternalStorage::Client',
    );
    ok( !$client, 'Client fails to instantiate without ServiceURL' );
}

# Test Store passes content-type from attachment
{
    my $client = RT::ExternalStorage::Client->new(
        Type       => 'RT::ExternalStorage::Client',
        ServiceURL => 'http://localhost:9999',
    );
    ok( $client, 'Client instantiated for Store test' );

    # Create a mock attachment with ContentType
    my $mock_attachment = Test::MockObject->new();
    $mock_attachment->mock( 'ContentType', sub { 'image/png' } );

    # Mock the UA to capture the request
    my $captured_request;
    my $mock_ua = Test::MockObject->new();
    my $mock_response = Test::MockObject->new();
    $mock_response->mock( 'is_success', sub { 1 } );
    $mock_ua->mock( 'request', sub {
        my ($self, $req) = @_;
        $captured_request = $req;
        return $mock_response;
    });
    $client->{_ua} = $mock_ua;

    my ($key, $msg) = $client->Store( 'abc123sha', 'file-content', $mock_attachment );
    is( $key, 'abc123sha', 'Store returns the SHA key on success' );
    ok( $captured_request, 'HTTP request was made' );
    is( $captured_request->method, 'PUT', 'Store uses PUT method' );
    like( $captured_request->uri, qr{/store/abc123sha$}, 'Store targets correct URL' );
    is( $captured_request->header('Content-Type'), 'image/png',
        'Store passes content-type from attachment' );
    is( $captured_request->content, 'file-content', 'Store sends correct content' );
}

# Test Store uses default content-type when no attachment
{
    my $client = RT::ExternalStorage::Client->new(
        Type       => 'RT::ExternalStorage::Client',
        ServiceURL => 'http://localhost:9999',
    );

    my $captured_request;
    my $mock_ua = Test::MockObject->new();
    my $mock_response = Test::MockObject->new();
    $mock_response->mock( 'is_success', sub { 1 } );
    $mock_ua->mock( 'request', sub {
        my ($self, $req) = @_;
        $captured_request = $req;
        return $mock_response;
    });
    $client->{_ua} = $mock_ua;

    my ($key, $msg) = $client->Store( 'def456sha', 'some-content', undef );
    is( $key, 'def456sha', 'Store returns SHA key without attachment' );
    is( $captured_request->header('Content-Type'), 'application/octet-stream',
        'Store uses default content-type when no attachment' );
}

# Test Get operation
{
    my $client = RT::ExternalStorage::Client->new(
        Type       => 'RT::ExternalStorage::Client',
        ServiceURL => 'http://localhost:9999',
    );

    my $mock_ua = Test::MockObject->new();
    my $mock_response = Test::MockObject->new();
    $mock_response->mock( 'is_success', sub { 1 } );
    $mock_response->mock( 'decoded_content', sub { 'retrieved-content' } );
    $mock_ua->mock( 'get', sub { return $mock_response } );
    $client->{_ua} = $mock_ua;

    my ($content, $msg) = $client->Get('abc123sha');
    is( $content, 'retrieved-content', 'Get returns content on success' );
}

# Test Get failure
{
    my $client = RT::ExternalStorage::Client->new(
        Type       => 'RT::ExternalStorage::Client',
        ServiceURL => 'http://localhost:9999',
    );

    my $mock_ua = Test::MockObject->new();
    my $mock_response = Test::MockObject->new();
    $mock_response->mock( 'is_success', sub { 0 } );
    $mock_response->mock( 'status_line', sub { '404 Not Found' } );
    $mock_ua->mock( 'get', sub { return $mock_response } );
    $client->{_ua} = $mock_ua;

    my ($content, $msg) = $client->Get('missing-sha');
    ok( !defined $content, 'Get returns undef on failure' );
    like( $msg, qr/404 Not Found/, 'Get returns error message on failure' );
}

# Test Delete operation
{
    my $client = RT::ExternalStorage::Client->new(
        Type       => 'RT::ExternalStorage::Client',
        ServiceURL => 'http://localhost:9999',
    );

    my $mock_ua = Test::MockObject->new();
    my $mock_response = Test::MockObject->new();
    $mock_response->mock( 'is_success', sub { 1 } );
    $mock_ua->mock( 'delete', sub { return $mock_response } );
    $client->{_ua} = $mock_ua;

    my ($key, $msg) = $client->Delete('abc123sha');
    is( $key, 'abc123sha', 'Delete returns SHA key on success' );
}

# Test Delete failure
{
    my $client = RT::ExternalStorage::Client->new(
        Type       => 'RT::ExternalStorage::Client',
        ServiceURL => 'http://localhost:9999',
    );

    my $mock_ua = Test::MockObject->new();
    my $mock_response = Test::MockObject->new();
    $mock_response->mock( 'is_success', sub { 0 } );
    $mock_response->mock( 'status_line', sub { '500 Internal Server Error' } );
    $mock_ua->mock( 'delete', sub { return $mock_response } );
    $client->{_ua} = $mock_ua;

    my ($key, $msg) = $client->Delete('fail-sha');
    ok( !defined $key, 'Delete returns undef on failure' );
    like( $msg, qr/500 Internal Server Error/, 'Delete returns error message on failure' );
}

# Test Store failure
{
    my $client = RT::ExternalStorage::Client->new(
        Type       => 'RT::ExternalStorage::Client',
        ServiceURL => 'http://localhost:9999',
    );

    my $mock_ua = Test::MockObject->new();
    my $mock_response = Test::MockObject->new();
    $mock_response->mock( 'is_success', sub { 0 } );
    $mock_response->mock( 'status_line', sub { '503 Service Unavailable' } );
    $mock_ua->mock( 'request', sub { return $mock_response } );
    $client->{_ua} = $mock_ua;

    my ($key, $msg) = $client->Store( 'fail-sha', 'content', undef );
    ok( !defined $key, 'Store returns undef on failure' );
    like( $msg, qr/503 Service Unavailable/, 'Store returns error message on failure' );
}

# Test DownloadURLFor
{
    my $client = RT::ExternalStorage::Client->new(
        Type       => 'RT::ExternalStorage::Client',
        ServiceURL => 'http://localhost:8080',
    );

    my $mock_attachment = Test::MockObject->new();
    $mock_attachment->mock( 'isa', sub {
        my ($self, $class) = @_;
        return $class eq 'RT::Attachment';
    });
    $mock_attachment->mock( '__Value', sub { 'sha256digest' } );

    my $url = $client->DownloadURLFor($mock_attachment);
    is( $url, 'http://localhost:8080/store/sha256digest',
        'DownloadURLFor returns correct URL' );
}

# Test that ExternalStorage PostLoadCheck uses Client when $ExternalStorageURL is set
{
    # Save original state
    my $original_storage = RT->System->ExternalStorage;

    RT->Config->Set( 'ExternalStorageURL', 'http://test-service:8080' );
    RT->Config->Set( 'ExternalStorage' );  # clear any existing backend config

    # Re-run PostLoadCheck
    RT->Config->PostLoadCheck;

    my $storage = RT->System->ExternalStorage;
    ok( $storage, 'ExternalStorage is set after PostLoadCheck with ExternalStorageURL' );
    isa_ok( $storage, 'RT::ExternalStorage::Client', 'ExternalStorage is a Client instance' );
    is( $storage->ServiceURL, 'http://test-service:8080', 'Client has correct ServiceURL' );

    # Restore original state
    RT->Config->Set( 'ExternalStorageURL', undef );
    RT->System->ExternalStorage($original_storage);
}

done_testing();
