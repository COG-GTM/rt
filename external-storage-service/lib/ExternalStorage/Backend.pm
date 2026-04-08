use warnings;
use strict;

package ExternalStorage::Backend;

use Role::Basic;

requires 'Init';
requires 'Get';
requires 'Store';
requires 'DownloadURLFor';
requires 'Delete';

sub new {
    my $class = shift;
    my %args = @_;

    my $type = delete $args{Type};
    if (not $type) {
        warn "No storage engine type provided\n";
        return undef;
    }

    my $target_class = "ExternalStorage::$type";
    eval "require $target_class";
    if ($@) {
        warn "Can't load external storage engine $target_class: $@\n";
        return undef;
    }

    unless ($target_class->DOES("ExternalStorage::Backend")) {
        warn "External storage engine $target_class doesn't implement ExternalStorage::Backend\n";
        return undef;
    }

    my $self = bless \%args, $target_class;
    return $self->Init;
}

1;
