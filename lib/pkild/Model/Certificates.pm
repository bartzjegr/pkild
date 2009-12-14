package pkild::Model::Certificates;

use strict;
use base 'Catalyst::Model::File';

__PACKAGE__->config(
    root_dir => '/var/tmp/certificate_authority',
);

################################################################################
# Return a list of hashes of lists of hashes that describe the directory tree
################################################################################
sub tree{
    my ($self, $c)=@_;
    my $tree;
    my @file_names=$self->list(mode => 'both', recurse =>1);
    my $rootdir=join("/",@{ $self->{'root_dir'}->{'dirs'} });
    $rootdir=~s/^\///;
    @file_names=sort(@file_names);
    my $previous_node='';
    for my $node (@file_names){
        next if $node eq '.';
        $node=~s/$rootdir//g;
        $node=~s/^\///g;
        my @part=split('\/',$node);
        my @oldpart=split('\/',$previous_node);
        for(my $depth=0; $depth<= $#part; $depth++){
            if($part[$depth] ne $oldpart[$depth]){
                push( $tree->[$depth], { 'name' => $part[$depth]; });
            }   
        }
        $previous_node=$node;
    }
    return $tree;
}

=head1 NAME

pkild::Model::Certificates - Catalyst File Model

=head1 SYNOPSIS

See L<pkild>

=head1 DESCRIPTION

L<Catalyst::Model::File> Model storing files under
L<>

=head1 AUTHOR

James White

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
