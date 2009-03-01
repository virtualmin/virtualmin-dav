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
&open_tempfile(FILE, ">".&digest_file($_[0]));
foreach $u (@{$_[1]}) {
	&print_tempfile(FILE, $u->{'user'},":",$u->{'dom'},":",$u->{'pass'},"\n");
	}
&close_tempfile(FILE);
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



1;

