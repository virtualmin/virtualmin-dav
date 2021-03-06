#!/usr/local/bin/perl
# Update the DAV authentication mode and users
use strict;
use warnings;
our (%in, %text, %config);

require './virtualmin-dav-lib.pl';
require './virtual_feature.pl';
&ReadParse();
$in{'dom'} || &error($text{'index_edom'});
my $d = &virtual_server::get_domain($in{'dom'});
$d || &error($text{'index_edom2'});
my $ddesc = &virtual_server::domain_in($d);

# Make sure something was done
&error_setup($text{'save_err'});
$d->{'dav_auth'} ||= $config{'auth'};
$d->{'dav_name_mode'} = $config{'name_mode'} if (!defined($d->{'dav_name_mode'}));
if ($in{'auth'} eq $d->{'dav_auth'} &&
    $in{'mode'} == $d->{'dav_name_mode'}) {
	&error($text{'save_enone'});
	}

&ui_print_header($ddesc, $text{'save_title'}, "");

# Get current users
my @davusers = &list_users($d);
my @allusers = &virtual_server::list_domain_users($d);
my @users;
foreach my $davu (@davusers) {
	my ($u) = grep { &dav_username($_, $d) eq $davu->{'user'} } @allusers;
	if ($u && (defined($u->{'plainpass'}) || $u->{'pass_digest'} ||
		   $u->{'domainowner'})) {
		push(@users, $u);
		}
	}

$d->{'dav_auth'} = $in{'auth'};
$d->{'dav_name_mode'} = $in{'mode'};

# Re-create the Apache directives
&feature_delete($d);
&feature_setup($d);

# Re-create all users
&$virtual_server::first_print($text{'save_recreate'});
my $file = &digest_file($d);
no strict "subs";
&virtual_server::open_tempfile_as_domain_user($d, TRUNC, ">$file", 1, 1);
&virtual_server::close_tempfile_as_domain_user($d, TRUNC);
use strict "subs";
foreach my $u (@users) {
	my $davu = { 'user' => &dav_username($u, $d),
		     'enabled' => 1 };
	my ($ppass, $upass, $dpass);
	if ($u->{'domainowner'}) {
		$ppass = $d->{'pass'};
		$upass = $d->{'enc_pass_crypt'};
		$dpass = $d->{'enc_pass_digest'};
		}
	else {
		$ppass = $u->{'plainpass'};
		$upass = $u->{'pass_crypt'};
		$dpass = $u->{'pass_digest'};
		}
	if ($d->{'dav_auth'} eq 'Basic') {
		# Unix crypted password
		if ($ppass) {
			my $salt = substr(time(), -2);
			$davu->{'pass'} = &unix_crypt($ppass, $salt);
			}
		else {
			$davu->{'pass'} = $upass;
			}
		}
	else {
		# DAV password
		if ($ppass) {
			$davu->{'pass'} = &htaccess_htpasswd::digest_password(
				$davu->{'user'}, $d->{'dom'}, $ppass);
			}
		else {
			$davu->{'pass'} = $dpass;
			}
		$davu->{'dom'} = $d->{'dom'};
		$davu->{'digest'} = 1;
		}
	&virtual_server::write_as_domain_user($d,
		sub { &htaccess_htpasswd::create_user($davu, $file) });
	}
&$virtual_server::second_print($virtual_server::text{'setup_done'});

# Update the domain
&$virtual_server::first_print($text{'save_save'});
&virtual_server::save_domain($d);
&$virtual_server::second_print($virtual_server::text{'setup_done'});

&virtual_server::run_post_actions();
&webmin_log("modify", "auth", undef, { 'dom' => $d->{'dom'} });

&ui_print_footer("index.cgi?dom=$in{'dom'}", $text{'index_return'});

