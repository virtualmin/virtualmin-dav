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
my ($d, $s) = @_;
my @ports = ( $d->{'web_port'} );
if ($d->{'ssl'}) {
	push(@ports, $d->{'web_sslport'});
	}
my $phtml = &virtual_server::public_html_dir($d);
foreach my $p (@ports) {
	my ($virt, $vconf, $conf) = &virtual_server::get_apache_virtual(
					$d->{'dom'}, $p);
	next if (!$virt);
	# XXX existing aliases!
	&apache::save_directive("Alias",
				[ "/dav/$s->{'dir'} $phtml/$s->{'dir'}" ],
				$vconf, $conf);
	my $loc = { 'name' => 'Location',
		    'value' => "/dav/$s->{'dir'}",
		    'members' => [ ] };
	&flush_file_lines($virt->{'file'});
	}
# XXX
# XXX pick and create users file
}

# delete_dav_share(&domain, &share)
# Removes the alias and location for a DAV share, and deletes the users file
sub delete_dav_share
{
my ($d, $s) = @_;
# XXX
}

# modify_dav_share(&domain, &share
# Updates the description for a DAV share
sub modify_dav_share
{
my ($d, $s) = @_;
# XXX
}

# add_dav_directives(&dom, port, [subdir])
# Finds a matching Apache virtualhost section, and adds the DAV directives
sub add_dav_directives
{
local ($d, $port, $dir) = @_;
local ($virt, $vconf) = &virtual_server::get_apache_virtual($d->{'dom'}, $port);
return 0 if (!$virt);

# Add Alias if missing
local $phtml = &virtual_server::public_html_dir($d);
local @aliases = &apache::find_directive("Alias", $vconf);
local $davpath = "/dav".($dir ? "/".$dir : "");
local $dirpath = $phtml.($dir ? "/".$dir : "");
local $avalue = $davpath." ".$dirpath;
if (&indexof($avalue, @aliases) < 0) {
	push(@aliases, $avalue);
	&apache::save_directive("Alias", \@aliases, $vconf, $conf);
	}

# Add Location if missing
local $passwd_file = &digest_file($d);
local @locs = &apache::find_directive_struct("Location", $vconf);
local ($loc) = grep { $_->{'words'}->[0] eq $davpath } @locs;
if (!$loc) {
	local $at = $d->{'dav_auth'};
	local $auf = $at eq "Digest" &&
		     $apache::httpd_modules{'core'} < 2.2 ?
			"AuthDigestFile" : "AuthUserFile";
	local @mems = (
		{ 'name' => 'DAV', 'value' => 'on' },
		{ 'name' => 'AuthType', 'value' => $at },
		{ 'name' => 'AuthName', 'value' => $d->{'dom'} },
		{ 'name' => $auf, 'value' => $passwd_file },
		{ 'name' => 'Require', 'value' => 'valid-user' },
		{ 'name' => 'ForceType', 'value' => 'text/plain' },
		{ 'name' => 'Satisfy', 'value' => 'All' },
		);
	if ($at eq "Digest" && $apache::httpd_modules{'core'} >= 2.2) {
		push(@mems, { 'name' => 'AuthDigestProvider',
			      'value' => 'file' });
		}
	if (defined(&virtual_server::list_available_php_versions)) {
		# Turn off fast CGI handling of .php* scripts when they
		# are accessed via DAV
		push(@mems, { 'name' => 'RemoveHandler', 'value' => '.php' });
		foreach my $v (
		    &virtual_server::list_available_php_versions($d)) {
			push(@mems, { 'name' => 'RemoveHandler',
				      'value' => '.php'.$v->[0] });
			}
		}
	if ($apache::httpd_modules{'mod_rewrite'}) {
		push(@mems, { 'name' => 'RewriteEngine', 'value' => 'off' });
		}
	$loc = { 'name' => 'Location',
		 'value' => $davpath,
		 'type' => 1,
		 'members' => \@mems };
	&apache::save_directive_struct(undef, $loc, $vconf, $conf);
	}
&flush_file_lines($virt->{'file'});
return 1;
}

# remove_dav_directives(&domain, port, [subdir])
sub remove_dav_directives
{
local ($d, $port, $dir) = @_;
local ($virt, $vconf) = &virtual_server::get_apache_virtual($d->{'dom'}, $port);
return 0 if (!$virt);

# Remove the alias
local $phtml = &virtual_server::public_html_dir($d);
local @aliases = &apache::find_directive("Alias", $vconf);
local $davpath = "/dav".($dir ? "/".$dir : "");
local $dirpath = $phtml.($dir ? "/".$dir : "");
local $avalue = $davpath." ".$dirpath;
local $idx = &indexof($avalue, @aliases);
if ($idx >= 0) {
	splice(@aliases, $idx, 1);
	&apache::save_directive("Alias", \@aliases, $vconf, $conf);
	}

# Remove the Location
local @locs = &apache::find_directive_struct("Location", $vconf);
local ($loc) = grep { $_->{'words'}->[0] eq $davpath } @locs;
if ($loc) {
	&apache::save_directive_struct($loc, undef, $vconf, $conf);
	}
if ($loc || $idx >= 0) {
	&flush_file_lines($virt->{'file'});
	return 1;
	}
return 0;
}

1;

