use strict;
use warnings;
use RT::Test::REST2 tests => undef;
use Test::Deep;

my $mech = RT::Test::REST2->mech;
my $auth = RT::Test::REST2->authorization_header;
my $rest_base_path = '/REST/2.0';
my $user = RT::Test::REST2->user;

my $queue = RT::Test->load_or_create_queue( Name => "General" );

my %cf;
for my $spec ( [ Single => 'FreeformSingle' ], [ Multi => 'FreeformMultiple' ], [ Empty => 'FreeformSingle' ] ) {
    my $cf = RT::CustomField->new( RT->SystemUser );
    my ( $ok, $msg ) = $cf->Create( Name => $spec->[0], Type => $spec->[1], Queue => $queue->Id );
    ok( $ok, $msg );
    $cf{ $spec->[0] } = $cf;
}

$user->PrincipalObj->GrantRight( Right => $_ ) for qw/ShowTicket SeeQueue SeeCustomField/;

my @tickets;
for my $n ( 1 .. 3 ) {
    my $ticket = RT::Ticket->new( RT->SystemUser );
    my ( $id, undef, $msg ) = $ticket->Create(
        Queue                                  => $queue->Id,
        Subject                                => "CF batch $n",
        'CustomField-' . $cf{Single}->Id       => "single $n",
        'CustomField-' . $cf{Multi}->Id        => [ "b$n", "a$n", "c$n" ],
    );
    ok( $id, $msg );
    push @tickets, $ticket;
}

my %expected_multi = map {
    my $ticket = $tickets[ $_ - 1 ];
    ( $ticket->Id => [ map { $_->Content } @{ $ticket->CustomFieldValues( $cf{Multi}->Id )->ItemsArrayRef } ] )
} 1 .. 3;

$RT::Handle->ClearSQLStatementLog;
$RT::Handle->LogSQLStatements(1);
my $res = $mech->get( "$rest_base_path/tickets?query=Queue='General'&fields=CustomFields&orderby=id", 'Authorization' => $auth );
$RT::Handle->LogSQLStatements(0);
is( $res->code, 200 );

my $ocfv_queries = grep { $_->[1] =~ /\bObjectCustomFieldValues\b/i } $RT::Handle->SQLStatementLog;
is( $ocfv_queries, scalar @tickets, 'one ObjectCustomFieldValues query per ticket' );

my $content = $mech->json_response;
is( scalar @{ $content->{items} }, 3 );
for my $item ( @{ $content->{items} } ) {
    my $n = ( grep { $tickets[$_]->Id == $item->{id} } 0 .. 2 )[0] + 1;
    cmp_deeply(
        $item->{CustomFields},
        bag(
            { name => 'Single', id => $cf{Single}->Id, type => 'customfield', _url => ignore(), values => ["single $n"] },
            { name => 'Multi',  id => $cf{Multi}->Id,  type => 'customfield', _url => ignore(), values => $expected_multi{ $item->{id} } },
            { name => 'Empty',  id => $cf{Empty}->Id,  type => 'customfield', _url => ignore(), values => [] },
        ),
        "custom field values for ticket $n"
    );
}

$user->PrincipalObj->RevokeRight( Right => 'SeeCustomField' );
$user->PrincipalObj->GrantRight( Right => 'SeeCustomField', Object => $cf{Single} );
$res = $mech->get( "$rest_base_path/tickets?query=Queue='General'&fields=CustomFields&orderby=id", 'Authorization' => $auth );
is( $res->code, 200 );
for my $item ( @{ $mech->json_response->{items} } ) {
    cmp_deeply(
        [ map { $_->{name} } @{ $item->{CustomFields} } ],
        ['Single'],
        'only custom fields the user can see are returned'
    );
}

done_testing;
