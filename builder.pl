#!/usr/bin/perl
use strict;
use warnings;
use lib qw( ./lib/perl5 );
use YAML;


sub init {

}

sub build {

    my $git = config->{'git_bin'};
    my $out = '' ;
    my @repos = body_parameters->get_all('repos');

    my ( $server ) = grep { request->header('host') =~ m/$_/ } keys %{ config->{'servers'} };
    my $sd = config->{'servers'}->{$server}->{'sync_dir'};

    # generate project version and write to the file
    my $version = _generate_version();
    my $version_file = _create_version_file( $sd, $version );

    # append the individual repo hashes
    for my $r ( @repos ) {
        my $lout = '';
        if ( chdir $r ) {
            $out .= "changed to directory $r during packaging<br />\n";
        } else {
            $out .= "cannot change directories to $r to package<br />\n";
            next;
        }
        $lout .= "$r : ";
        $lout .= `$git log -1 --format=%H`;
        $out .= $lout . "<br />\n";
        $lout .= "\n\n";
        _append_to_version_file( $version_file, $lout );

    }

    # move version file into place
    rename "$sd/$version_file", "$sd/VERSION";


    # package it up here
    if ( chdir $sd ) {
        $out .= sprintf 'changed directory to %s to publish code%s', $sd, "\n";
        my $cmd = sprintf '%s czf ../project-%s-%s.tar.gz ./*', config->{'tar_bin'}, $server, $version;

        if ( open my $pipe, '-|', $cmd ) {
            local $/ = undef;
            $out .= <$pipe>;
            close $pipe;
        } else {
            $out .= sprintf 'failed to run %s due to %s%s', $cmd, $!, "\n";
        }

    } else {
        $out .= sprintf 'cannot change directory to %s to publish code%s', $sd, "\n";
    }


    return $out;
}
sub _generate_version {}
sub _get_version {}
sub _get_version_extended_info {}
sub _create_version_file {}
sub _append_to_version_file {}

