#!/usr/bin/perl
use strict;
use warnings;
use lib qw( ./lib/perl5 );
use Dancer2;
use Dancer2::Plugin::Auth::SimpleLDAP;

my $prefix = config->{'prefix'} || '/sm';

sub stage {

    my $version = shift || 1;
    my $status = 'success';

    if ( 1 == $version ) {
        content_type 'text/plain';
    } else {
        content_type 'text/html';
    }

    my $git = config->{'git_bin'};
    my $out = '' ;
    my @repos = body_parameters->get_all('repos');
    for my $r ( @repos ) {
        if ( chdir $r ) {
            $out .= "changed to directory  $r during staging\n";
        } else {
            $out .= "cannot change directories to $r to stage\n";
            $status = 'failure';
            next;
        }
        my $branch = body_parameters->get( $r );
        $out .= "\$ $git fetch\n";
        $out .= `$git fetch 2>&1`;
        $out .= "\$ $git checkout $branch; $git reset --hard origin/$branch\n";
        $out .= `$git checkout $branch 2>&1; $git reset --hard origin/$branch 2>&1`;
        $out .= "\n\n";
    }

    if ( 1 == $version ) {
        return $out;
    } else {
        $out =~ s{\n}{<br />\n}g;
        return menu( 2, $status, $out );
    }
}

sub build {
    content_type 'text/html';
    my $status = 'success';

    my $git = config->{'git_bin'};
    my $out = '' ;
    my @repos = body_parameters->get_all('repos');

    my ( $server ) = grep { request->header('host') =~ m/$_/ } keys %{ config->{'servers'} };
    my $sd = config->{'servers'}->{$server}->{'sync_dir'};

    # generate project version and write to the file
    my $version = _generate_version();
    my $version_file = _version_file( $sd, $version );
    _append_to_version_file( $version_file, $version );

    # append the individual repo hashes
    for my $r ( @repos ) {
        my $lout = "\n";
        my $hash = _get_git_hash( $r );
        if ( $hash ) {
            $out .= "changed to directory $r during packaging<br />\n";
        } else {
            $out .= "cannot change directories to $r to package<br />\n";
            $status = 'failure';
            next;
        }
        $lout .= "$r : ";
        $lout .= $hash;
        $out  .= $lout . "<br />\n";
        unless (
            _append_to_version_file( $version_file, $lout )
        ) {
            $status = 'failure';
            $out .= "<p>failed to append to $version_file</p>\n";
        }

    }

    # move version file into place
    unless (
        rename $version_file, "$sd/META/VERSION"
    ) {
        $status = 'failure';
        $out .= "<p>failed to rename $version_file to $sd/META/VERSION : $!</p>\n";
    }

#    # package it up here
#    if ( chdir $sd ) {
#        $out .= sprintf 'changed directory to %s to package code%s', $sd, "<br />\n";
#        my $cmd = sprintf '%s -s dir -t rpm -v %s -f -n %s %s/.=%s', config->{'fpm_bin'}, $version, $server, $server, $sd;
#
#        if ( open my $pipe, '-|', $cmd ) {
#            local $/ = undef;
#            $out .= <$pipe>;
#            close $pipe;
#        } else {
#            $out .= sprintf 'failed to run %s due to %s%s', $cmd, $!, "<br />\n";
#        }
#    } else {
#        $out .= sprintf 'cannot change directory to %s to package code%s', $sd, "<br />\n";
#    }

    return menu( 2, $status, $out );
}


sub publish {
    my $out = '';
    my $sync_failures = 0;
    my $status = 'success';

    content_type 'text/html';

    my @repos = body_parameters->get_all('repos');
    my $okay_so_far = 1;
    for my $r ( @repos ) {
        my $branch = body_parameters->get( $r );
        if ( $branch ne 'master' ) {
            $okay_so_far = 0;
            $out .= sprintf 'repo %s is set to branch %s rather than master so aborting publication%s', $r, $branch, "\n";
            last;
        }
    }

    my ( $server ) = grep { request->header('host') =~ m/$_/ } keys %{ config->{'servers'} };
    my $sd = config->{'servers'}->{$server}->{'sync_dir'};
    if ( $okay_so_far ) {
        if ( chdir $sd ) {
            $out .= sprintf 'changed directory to %s to publish code%s', $sd, "<br />\n";
            my $cmd = sprintf './%s', config->{'sync_bin'};

            if ( open my $pipe, '-|', $cmd ) {
                local $/ = undef;
                $out .= <$pipe>;
                close $pipe or $sync_failures++;
            } else {
                $out .= sprintf 'failed to run %s due to %s%s', $cmd, $!, "\n";
                $sync_failures++;
            }

        } else {
             $out .= sprintf 'cannot change directory to %s to publish code%s', $sd, "\n";
        }
    } else {
        $out .= "<p>failed to change directory to $sd : $!</p>";
        $status = 'failure';
    }

    if ( $sync_failures ) {
        $out .= "<h3>Some servers failed to sync!</h3>\n";
        $status = 'failure';
        require "$sd/commonlib/lib/Common/Email.pm";
        Common::Email::send(
            sprintf
'To: %s
From: Staging-Manager <sm@example.com>
Subject: Publication did not succeed to all servers. Please check output closely.

%s

', params->{'un'}, $out
        );
    }

    menu( 2, $status, $out );
}

sub process_login {
    redirect $prefix;
}

sub login_form {
    template 'login', { 'prefix' => $prefix };
}

sub menu {

    my $version = $_[0] || 1;
    my $status  = $_[1] || 'success';
    my $status_message = $_[2] || '';


    my ( $server ) = grep { request->header('host') =~ m/$_/ } keys %{ config->{'servers'} };
    my @repos = _find_git_repos( config->{'servers'}->{$server}->{'repo_dirs'} );

    my $sf;
    $sf .= template 'staging_entry', $_ for @repos;

    my @v = (
        sub {},
        sub {
            my $can_publish = ( scalar @repos == ( grep { $_->{'branch'} eq 'master' } @repos ) );
            my $publishing_disabled = $can_publish ? '' : q{ disabled='disabled'};
            my $pf;
            $pf .= ( template 'publishing_entry', $_, { layout => undef } ) for @repos;

            template 'menu', {
                'prefix'                => $prefix,
                'staging_form'          => $sf,
                'publishing_form'       => $pf,
                'publishing_disabled'   => $publishing_disabled,
            };
        },
        sub {
            my $version = _get_version();
            my $ve = '<p>' . ( join "<br />\n", _get_version_extended_info() ) . '</p>';
            my $pf;
            $pf .= ( template 'publishing_entry', $_, { layout => undef } ) for @repos;

            template 'v2_menu', {
                'prefix'                => $prefix,
                'staging_form'          => $sf,
                'version'               => $version,
                'version_extended_info' => $ve,
                'publishing_form'       => $pf,
                'status_message'        => $status_message,
                'status'                => $status,
            };
        },
    );

    $v[ $version ]->();
}


sub _generate_version {
    my @t = ( gmtime() )[ 5, 4, 3, 2, 1, 0 ];
    $t[0] += 1900;
    $t[1] += 1;
    my $v = sprintf '%04d%02d%02d.%02d%02d%02d', @t;
    return $v;
}

sub _get_version {
    my $v = ( _get_version_extended_info() )[ 0 ];

    return ( $v ? $v : 0 );
}

sub _get_version_extended_info {
    my ( $server ) = grep { request->header('host') =~ m/$_/ } keys %{ config->{'servers'} };
    my $sd = config->{'servers'}->{$server}->{'sync_dir'};
    my $fn = "$sd/META/VERSION";
    my @info;

    if ( open my $vf, '<', $fn ) {
        @info = <$vf>;
    }

    return @info;
}

sub _version_file {
    my ( $d, $f ) = @_;
    my $fn = sprintf '%s/META/%s', $d, $f;
    return $fn;
}

sub _append_to_version_file {
    my ( $f, $c ) = @_;
    my $s = 0;
    my @r = ( "cannot append to $f", "cannot complete writing to $f", "success" );
    my $rs;

    if ( open my $file, '>>', $f ) {
        $s = 1;
        print {$file} $c;
        if ( close $file ) {
            $s = 2;
        }
    }

    $rs = sprintf '%s : %s', $r[ $s ], ( $s ? $! : 'written' );

    return ( $s, $rs );
}

sub _find_git_repos {
    my $repo_dirs = shift;
    my @repos = ();
    for my $dir ( keys %{ $repo_dirs } ) {
        my @subdirs = ();
        if ( $repo_dirs->{$dir}[0] eq '_ALL_' ) {
            chdir $dir or die "cannot change directory to $dir\n";
            opendir my $d, $dir or die "cannot read directory $dir\n";
            @subdirs = grep { -d $_ && $_ !~ m/^\./ } readdir $d;
            closedir $d;
        } else {
            @subdirs =  @{ $repo_dirs->{$dir} };
        }

        for my $repo ( @subdirs ) {
            next if $repo =~ m/^(?:sm|stage-manager)$/;
            my $path = sprintf '%s/%s', $dir, $repo;
            my $branch = _get_git_branch( $path );
            my $hash   = _get_git_hash(   $path );
            my $s_hash = _get_git_hash(   $path, 1 );
            push @repos, {
                'repo'   => $path,
                'branch' => $branch,
                'class'  => $branch,
                'hash'   => $hash,
                's_hash' => $s_hash,
            };
        }
    }

    return @repos;
}

sub _get_git_branch {
    my $path = shift;
    my $git = config->{'git_bin'};
    chdir $path or die "cannot change directory path to $path to check its git branch.\n";
    my ( $branch ) = grep { m/^\Q* \E(\S+)/ } (split /\n/, `$git branch`);
    $branch =~ s/^\Q* \E//;
    return $branch;
}

sub _get_git_hash {
    my ( $path, $short ) = @_;
    my $git = config->{'git_bin'};

    chdir $path or return 0;
    my $format = $short ? '%h' : '%H';
    return `$git log -1 --format=$format`;
}


sub _force_https {
    if ( request->scheme eq 'http' ) {
        redirect 'https://' . request->header('host') . request->request_uri, 307;
    }
}

prefix $prefix;
hook before        => sub { _force_https(); };
post '/stage'      => require_ldap_match sub { stage() };
post '/v2/stage'   => require_ldap_match sub { stage( 2 ) };
post '/v2/build'   => require_ldap_match sub { build(); };
post '/v2/publish' => require_ldap_match sub { publish(); };
post '/publish'    => require_ldap_match sub { publish() };
post '/login'      => require_ldap_match sub { process_login() };
get  '/login'      => sub { login_form() };
get  '/v2'         => sub { menu( 2 ) };
get  '/v2/'        => sub { menu( 2 ) };
get  '/'           => require_ldap_match sub { menu( 2 ) };
get  ''            => require_ldap_match sub { menu( 2 ) };
dance;

