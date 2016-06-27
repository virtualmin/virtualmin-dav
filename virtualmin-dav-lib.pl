# Common functions for DAV management
use strict;
use warnings;
our (%config);

BEGIN { push(@INC, ".."); };
eval "use WebminCore;";
&init_config();
&foreign_require("virtual-server", "virtual-server-lib.pl");
$config{'auth'} ||= "Digest";

# digest_file(&domain)
sub digest_file
{
return "$_[0]->{'home'}/etc/dav.digest.passwd";
}

# list_users(&domain)
sub list_users
{
my $users;
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
no strict "subs"; # XXX Lexical?
&virtual_server::open_tempfile_as_domain_user(
	$_[0], FILE, ">".&digest_file($_[0]));
foreach my $u (@{$_[1]}) {
	&print_tempfile(FILE, $u->{'user'},":",$u->{'dom'},":",$u->{'pass'},"\n");
	}
&virtual_server::close_tempfile_as_domain_user($_[0], FILE);
use strict "subs";
}

# dav_username(&user, &domain)
# Returns the DAV username for a user in some domain
sub dav_username
{
my ($user, $dom) = @_;
$dom->{'dav_name_mode'} = $config{'name_mode'} if (!defined($dom->{'dav_name_mode'}));
if ($dom->{'dav_name_mode'} == 0) {
	# user@domain mode
	my $un = &virtual_server::remove_userdom($user->{'user'}, $dom);
	return "$un\@$dom->{'dom'}";
	}
elsif ($dom->{'dav_name_mode'} == 2) {
	# domain\user mode
	my $un = &virtual_server::remove_userdom($user->{'user'}, $dom);
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
	if ($a->{'words'}->[0] =~ /^\/dav\/(\S+)$/ ||
	    $a->{'words'}->[0] eq "/dav") {
		my $dir = $a->{'words'}->[0] eq "/dav" ? "" : $1;
		$aliases{$dir} = $a;
		}
	}
my $auf = $d->{'dav_auth'} eq "Digest" &&
	  $apache::httpd_modules{'core'} < 2.2 ? "AuthDigestFile"
					       : "AuthUserFile";
my $phtml = &virtual_server::public_html_dir($d);
foreach my $l (&apache::find_directive_struct("Location", $vconf)) {
	if ($l->{'words'}->[0] =~ /^\/dav\/(\S+)$/ ||
	    $l->{'words'}->[0] eq "/dav") {
		# Found one
		my $dir = $l->{'words'}->[0] eq "/dav" ? "" : $1;
		next if (!$aliases{$dir});
		my $s = { 'dir' => $dir,
			  'main' => !$dir,
			  'fulldir' => $l->{'words'}->[0],
			  'location' => $l,
			  'alias' => $aliases{$dir},
			  'path' => $aliases{$dir}->{'words'}->[1],
		 	};
		$s->{'relpath'} = $s->{'path'};
		$s->{'relpath'} =~ s/^\Q$d->{'home'}\/\E//;
		$s->{'samepath'} = $s->{'path'} eq $phtml."/".$s->{'dir'};
		$s->{'realm'} = &apache::find_directive("AuthName",
							$l->{'members'}, 1);

		# Extract allowed users
		my $reqs = &apache::wsplit(
			&apache::find_directive("Require", $l->{'members'}));
		if ($reqs->[0] ne "valid-user") {
			shift(@$reqs);	# Remove 'user'
			$s->{'users'} = $reqs;
			}

		# Extract read-write users
		my ($limit) = &apache::find_directive_struct(
				"Limit", $l->{'members'});
		if ($limit) {
			my $reqs = &apache::wsplit(&apache::find_directive(
					"Require", $limit->{'members'}));
			if ($reqs->[0] ne "valid-user") {
				shift(@$reqs);	# Remove 'user'
				$s->{'rwusers'} = $reqs;
				}
			}
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
my $ok = 0;
foreach my $p (@ports) {
	$ok++ if (&add_dav_directives($d, $p, $s->{'dir'}, $s->{'path'},
				      $s->{'realm'}));
	}
no warnings "once";
undef(@apache::get_config_cache);
use warnings "once";
&modify_dav_share($d, $s);	# Set users
&virtual_server::register_post_action(\&virtual_server::restart_apache);
return $ok;
}

# delete_dav_share(&domain, &share)
# Removes the alias and location for a DAV share, and deletes the users file
sub delete_dav_share
{
my ($d, $s) = @_;
my @ports = ( $d->{'web_port'} );
if ($d->{'ssl'}) {
	push(@ports, $d->{'web_sslport'});
	}
my $ok = 0;
foreach my $p (@ports) {
	$ok++ if (&remove_dav_directives($d, $p, $s->{'dir'}, $s->{'path'}));
	}
&virtual_server::register_post_action(\&virtual_server::restart_apache);
return $ok;
}

# modify_dav_share(&domain, &share)
# Updates the description for a DAV share
sub modify_dav_share
{
my ($d, $s) = @_;
my @ports = ( $d->{'web_port'} );
if ($d->{'ssl'}) {
	push(@ports, $d->{'web_sslport'});
	}

foreach my $port (@ports) {
	my ($virt, $vconf, $conf) =
		&virtual_server::get_apache_virtual($d->{'dom'}, $port);
	next if (!$virt);

	# Find Alias and change path
	my $phtml = &virtual_server::public_html_dir($d);
	my @aliases = &apache::find_directive("Alias", $vconf);
	my $idx = -1;
	my $davpath = "/dav".($s->{'dir'} ? "/".$s->{'dir'} : "");
	for(my $i=0; $i<@aliases; $i++) {
		if ($aliases[$i] =~ /^\Q$davpath\E\s+(\S+)/) {
			$aliases[$i] = $davpath." ".$s->{'path'};
			last;
			}
		}
	&apache::save_directive("Alias", \@aliases, $vconf, $conf);

	# Find Location and change realm
	my @locs = &apache::find_directive_struct("Location", $vconf);
	my ($loc) = grep { $_->{'words'}->[0] eq $davpath } @locs;
	if ($loc) {
		&apache::save_directive("AuthName", [ "\"$s->{'realm'}\"" ],
					$loc->{'members'}, $conf);
		if ($s->{'users'}) {
			# Limit to some users
			&apache::save_directive("Require",
					[ join(" ", "user", @{$s->{'users'}}) ],
					$loc->{'members'}, $conf);
			}
		else {
			# Any user
			&apache::save_directive("Require", [ "valid-user" ],
						$loc->{'members'}, $conf);
			}

		# Save read-write users
		my ($limit) = &apache::find_directive_struct(
				"Limit", $loc->{'members'});
		if ($limit || $s->{'rwusers'}) {
			my $rwusers = join(" ", "user", @{$s->{'rwusers'}});
			if (!$limit) {
				# Add new block for some users
				&apache::save_directive_struct(
					undef,
					{ 'name' => 'Limit',
					  'value' => 'POST PUT DELETE',
					  'type' => 1,
					  'members' =>  [
					    { 'name' => 'Require',
					      'value' => $rwusers },
					  ]
					},
					$loc->{'members'}, $conf);
				}
			elsif ($s->{'rwusers'}) {
				# Limit to some users, in existing block
				&apache::save_directive("Require", [ $rwusers ],
						$limit->{'members'}, $conf);
				}
			else {
				# Any user, in existing block
				&apache::save_directive("Require",
						[ "valid-user" ],
						$limit->{'members'}, $conf);
				}
			}
		}
	&flush_file_lines($virt->{'file'});
	&virtual_server::register_post_action(\&virtual_server::restart_apache);
	}

return 1;
}

# add_dav_directives(&dom, port, [subdir, path, realm])
# Finds a matching Apache virtualhost section, and adds the DAV directives
sub add_dav_directives
{
my ($d, $port, $dir, $dirpath, $realm) = @_;
my ($virt, $vconf, $conf) =
	&virtual_server::get_apache_virtual($d->{'dom'}, $port);
return 0 if (!$virt);

# Add Alias if missing
my $phtml = &virtual_server::public_html_dir($d);
my @aliases = &apache::find_directive("Alias", $vconf);
my $davpath = "/dav".($dir ? "/".$dir : "");
$dirpath ||= $phtml;
my $avalue = $davpath." ".$dirpath;
if (&indexof($avalue, @aliases) < 0) {
	push(@aliases, $avalue);
	&apache::save_directive("Alias", \@aliases, $vconf, $conf);
	}

# Add Location if missing
my $passwd_file = &digest_file($d);
my @locs = &apache::find_directive_struct("Location", $vconf);
my ($loc) = grep { $_->{'words'}->[0] eq $davpath } @locs;
if (!$loc) {
	my $at = $d->{'dav_auth'};
	my $auf = $at eq "Digest" &&
		     $apache::httpd_modules{'core'} < 2.2 ?
			"AuthDigestFile" : "AuthUserFile";
	my @mems = (
		{ 'name' => 'DAV', 'value' => 'on' },
		{ 'name' => 'AuthType', 'value' => $at },
		{ 'name' => 'AuthName',
		  'value' => '"'.($realm || $d->{'dom'}).'"' },
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
	 	 'words' => [ $davpath ],
		 'type' => 1,
		 'members' => \@mems };
	&apache::save_directive_struct(undef, $loc, $vconf, $conf);
	}
&flush_file_lines($virt->{'file'});
return 1;
}

# remove_dav_directives(&domain, port, [subdir, path])
sub remove_dav_directives
{
my ($d, $port, $dir, $dirpath) = @_;
my ($virt, $vconf, $conf) =
	&virtual_server::get_apache_virtual($d->{'dom'}, $port);
return 0 if (!$virt);

# Remove the alias
my $phtml = &virtual_server::public_html_dir($d);
my @aliases = &apache::find_directive("Alias", $vconf);
my $idx = -1;
my $davpath = "/dav".($dir ? "/".$dir : "");
for(my $i=0; $i<@aliases; $i++) {
	if ($aliases[$i] =~ /^\Q$davpath\E\s/) {
		$idx = $i;
		last;
		}
	}
if ($idx >= 0) {
	splice(@aliases, $idx, 1);
	&apache::save_directive("Alias", \@aliases, $vconf, $conf);
	}

# Remove the Location
my @locs = &apache::find_directive_struct("Location", $vconf);
my ($loc) = grep { $_->{'words'}->[0] eq $davpath } @locs;
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

