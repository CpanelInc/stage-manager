package Dancer2::Plugin::Auth::SimpleLDAP;

use strict;
use warnings;
use utf8;
use Net::LDAP;
use Try::Tiny;
use Dancer2::Plugin;

register 'require_ldap_match' => sub {
    my $dsl     = shift;
    my $coderef = shift;
    return sub {
        my $app     = $dsl->app;
        my $request = $app->request;
        my $session = $app->session;
        my $params  = $request->params;
        my $config  = $app->{'config'}{'plugins'}{'Auth::SimpleLDAP'};
        my $login_url = $app->prefix . '/login';
        my $auth = 0;

        # Is the user logged in already, and if not did they send credentials?
        goto $coderef if ( $session->read( 'user' ) );
        return $dsl->redirect( $login_url ) unless ( $params->{'un'} && $params->{'pw'} );


        my ( $ldap, $limit_search, $user_search, @allowed_users, $site_user );
        try {
            $ldap = Net::LDAP->new( $config->{'host'}, onerror => 'die', 'raw' => qr/(?i:^jpegPhoto|;binary)/ );
            $ldap->bind or $dsl->debug( 'failed anon bind' );
        } catch {
            $dsl->debug( 'failed anonymous bind' );
            return $dsl->redirect( $login_url );
        };
        try {
            $limit_search = $ldap->search(
                'base'   => $config->{'basedn'},
                'filter' => $config->{'user_limit_filter'}
            );
            $user_search = $ldap->search(
                'base'   => $config->{'basedn'},
                'filter' => ( sprintf $config->{'user_filter'}, $params->{'un'} )
            );
        } catch {
            $dsl->debug( 'failed search for users' );
        };
        try {
            @allowed_users = $limit_search->entries;
            ( $site_user ) = $user_search->entries;
        } catch {
            $dsl->debug( 'LDAP search failed' );
        };
        try {
            foreach my $potential ( @allowed_users ) {
                next unless ( $potential->{'asn'}{'objectName'} eq $site_user->{'asn'}{'objectName'} );
                $ldap->bind( $site_user->{'asn'}{'objectName'}, 'password' => $params->{'pw'} );
                $session->write( 'user', $params->{'un'} );
                $session->{'is_dirty'} = 1;
                return $coderef->($dsl);
            }
            $dsl->debug(
                sprintf 'did not find user %s who submitted credentials within %s',
                (sprintf $config->{'user_filter'}, $params->{'un'}),
                $config->{'user_limit_filter'}
            );
        } catch {
            $dsl->info(
                sprintf 'login failed, user %s using filter %s (probably wrong password, bind as user failed, from %s',
                $params->{'un'},
                (sprintf $config->{'user_filter'}, $params->{'un'}),
                $request->remote_address
            );
        };
        return $dsl->redirect( $login_url ); # or something
    };
};


register_plugin for_versions => [2];

1;
