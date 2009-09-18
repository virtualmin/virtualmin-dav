# Common functions for DAV management

BEGIN { push(@INC, ".."); };
eval "use WebminCore;";
if ($@) {
	do '../web-lib.pl';
	do '../ui-lib.pl';
	}
&init_config();
$config{'auth'} ||= "Digest";

# digest_file(&domain)
sub digest_file
{
return "$_[0]->{'home'}/etc/dav.digest.passwd";
}

# list_users(&domain)
sub list_users
{
local $users;
&foreign_require("htaccess-htpasswd", "htaccess-lib.pl");
$_[0]->{'dav_auth'} ||= $config{'auth'};
if ($_[0]->{'dav_auth'} eq 'Digest') {
        $users = &htaccess_htpasswd::list_digest_users(&digest_file($_[0]));
        }
else {
        $users = &htaccess_htpasswd::list_users(&digest_file($_[0]));
        }
return @$users;
}

# save_users(&domain, &users)
sub save_users
{
local $u;
&virtual_server::open_tempfile_as_domain_user(
	$_[0], FILE, ">".&digest_file($_[0]));
foreach $u (@{$_[1]}) {
	&print_tempfile(FILE, $u->{'user'},":",$u->{'dom'},":",$u->{'pass'},"\n");
	}
&virtual_server::close_tempfile_as_domain_user($_[0], FILE);
}

# dav_username(&user, &domain)
# Returns the DAV username for a user in some domain
sub dav_username
{
local ($user, $dom) = @_;
$dom->{'dav_name_mode'} = $config{'name_mode'} if (!defined($dom->{'dav_name_mode'}));
if ($dom->{'dav_name_mode'} == 0) {
	# user@domain mode
	local $un = &virtual_server::remove_userdom($user->{'user'}, $dom);
	return "$un\@$dom->{'dom'}";
	}
elsif ($dom->{'dav_name_mode'} == 2) {
	# domain\user mode
	local $un = &virtual_server::remove_userdom($user->{'user'}, $dom);
	return "$dom->{'dom'}\\$un";
	}
else {
	# Unix username mode
	return $user->{'user'};
	}
}

# list_dav_shares(&domain)
# Returns a list of hash refs for sub-directories under public_html with /dav
# paths mapped to them.
sub list_dav_shares
{
my ($d) = @_;
my ($virt, $vconf, $conf) = &virtual_server::get_apache_virtual(
				$d->{'dom'}, $d->{'web_port'});
return ( ) if (!$virt);
my @rv;
my %aliases;
foreach my $a (&apache::find_directive_struct("Alias", $vconf)) {
	if ($a->{'words'}->[0] =~ /^\/dav\/(\S+)$/) {
		$aliases{$1} = $a;
		}
	}
my $auf = $d->{'dav_auth'} eq "Digest" &&
	  $apache::httpd_modules{'core'} < 2.2 ? "AuthDigestFile"
					       : "AuthUserFile";
foreach my $l (&apache::find_directive_struct("Location", $vconf)) {
	if ($l->{'words'}->[0] =~ /^\/dav\/(\S+)$/ && $aliases{$1}) {
		# Found one
		my $s = { 'dir' => $1,
			  'location' => $l,
			  'alias' => $aliases{$1},
			  'path' => $aliases{$1}->{'words'}->[1],
		 	};
		my $uf = &apache::find_directive($auf, $l->{'members'});
		$s->{'users'} = $uf;
		$s->{'realm'} = &apache::find_directive("AuthName",
							$l->{'members'});
		push(@rv, $s);
		}
	}
return @rv;
}

# create_dav_share(&domain, &share)
# Create a new share with the given directory and description
sub create_dav_share
{
my ($d, $share) = @_;
# XXX
# XXX pick and create users file
}

# delete_dav_share(&domain, &share)
# Removes the alias and location for a DAV share, and deletes the users file
sub delete_dav_share
{
my ($d, $share) = @_;
# XXX
}

# modify_dav_share(&domain, &share
# Updates the description for a DAV share
sub modify_dav_share
{
my ($d, $share) = @_;
# XXX
}

1;

